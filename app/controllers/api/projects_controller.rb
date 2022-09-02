class Api::ProjectsController < Api::ApiController
  before_action :need_admin, except: %i[index show model objects]
  before_action :set_project, only: %i[show update destroy model objects export]
  skip_before_action :header_authorization_verify, only: [:show]

  def index
    projects = projects_of_current_user
    result_project = projects.map do |project|
      records = project.evaluation_records
      project[:progress] = {
        self: records.count { |r| r.type == '自我评价' },
        anonymous: records.count { |r| r.type == '匿名评价' },
        city: records.count { |r| r.type == '市地工商联' && r.evaluating_user == @current_user },
        official: records.count { |r| r.type == '省工商联' }
      }
      project[:project_type] = project.evaluation_model.evaluation_type
      project
    end
    render json: { ok: true, projects: result_project }
  end

  def show
    evaluation_records = @project&.evaluation_records
    @project[:evaluation_records] = evaluation_records
    render json: { ok: true, project: @project }
  end

  def create
    project = Project.create!(project_params)
    render json: { ok: true, project: project }
  rescue StandardError
    render json: { ok: false, error: 'create_project_error' }, status: :internal_server_error
  end

  def update
    @project&.update!(name: params[:name]) if params[:name]

    if params[:status] == 'switch_review'
      @project.switch_review!
    elsif params[:status] == 'switch_complete'
      @project.switch_complete!
    end

    if params[:user_ids]
      return render json: { ok: false, error: 'project_in_review' }, status: :conflict unless @project&.open?

      @project&.update!(user_ids: params[:user_ids].uniq)
    end
    render json: { ok: true, project: @project }
  rescue StandardError
    render json: { ok: false, error: 'project_updated_error' }, status: :internal_server_error
  end

  def destroy
    @project&.destroy!
    render json: { ok: true }
  rescue StandardError
    render json: { ok: false, error: 'delete_project_error' }, status: :internal_server_error
  end

  def model
    evaluation_model = @project&.evaluation_model
    render json: { ok: true, model: evaluation_model }
  rescue StandardError
    render json: { ok: false, error: 'get_evaluation_model_error' }, status: :internal_server_error
  end

  def objects
    render json: { ok: true, objects: objects_of_current_user }
  end

  def export
    project = @project
    role_percentages = project&.evaluation_model&.role_percentages
    results = []
    evaluation_records = project&.evaluation_records&.map do |record|
      detaildata = []
      percentage = 0
      type = record[:type]
      role_percentages&.map do |role|
        percentage = role['percentage'] if role['role'] == type
      end
      sum_score = 0
      record[:records].map do |score|
        sum_score += score[:score].to_f
      end
      evaluations = project&.evaluation_model&.evaluations
      # 获取细分
      # detail_item_index 为小指标的index
      # evaluation_index 为大指标的index
      detail_item_index = 0
      evaluation_index = 1
      data = {}
      evaluations.map do |evaluation| # 一项大指标
        data['总分'] = 0
        sum_item_score = 0
        content = evaluation[:content]
        details = evaluation[:details] # 一堆小指标
        each_detail_item_index = 1
        details.map do |detail|
          sum_item_score += record[:records][detail_item_index][:score].to_f
          data[each_detail_item_index.to_s + '.' + detail[:item]] = record[:records][detail_item_index][:score]
          detail_item_index += 1
          each_detail_item_index += 1
        end
        data['总分'] = sum_item_score.to_s
        detaildata.push({ 'data' => data, 'content' => evaluation_index.to_s + '.' + content })
        data = {}
        evaluation_index += 1
      end
      detaildata.insert(0, detaildata.pop)
      score = sum_score * percentage.to_f
      user = User.without(:password_digest).find(record[:evaluated_user_id])[:company_name]
      flag = 0
      results.map do |result|
        next unless result['参评对象'] == user

        if result.key?('_' + type)
          item_index = 0
          detaildata.map do |item| # 大指标obj
            item['data'].keys.map do |detailname|
              result['_' + type][item_index]['data'][detailname] =
                result['_' + type][item_index]['data'][detailname].to_f + item['data'][detailname].to_f
            end
            item_index += 1
          end
        else
          result['_' + type] = detaildata
        end
        if !result[type].nil?
          result[type]['score'] += score
          result[type]['people'] += 1
        else
          result[type] = { 'score' => score, 'people' => 1 }
        end
        flag = 1
      end
      if flag.zero?
        results.push({ '参评对象' => user, type => { 'score' => score, 'people' => 1 }, '_' + type => detaildata })
      end
    end
    # ['参评对象','总分','等级','自我评价','自我评价人数','自我评价平均分']
    order_field = %w[参评对象 总分 等级]
    change_name = {
      '省工商联' => '综合评价平均分',
      '匿名评价' => '匿名评价平均分',
      '自我评价' => '自我评价平均分'
    }
    results.map do |result|
      all_score = 0
      role_percentages&.map do |role|
        unless order_field.include?(role[:role])
          order_field.append(role[:role] + '人数', change_name[role[:role]],
                             role[:role])
        end
        next if result[role[:role]].nil?

        result[role[:role] + '人数'] = result[role[:role]]['people']
        result[role[:role]] = result[role[:role]]['score'] / result[role[:role]]['people']
        result[role[:role]] = result[role[:role]].round(3)
        all_score += result[role['role']]

        result['_'+role[:role]]&.map do |detail|
          detail['data'].keys&.map do |itemkey|
            detail['data'][itemkey] =   detail['data'][itemkey].to_f / result[role[:role] + '人数']
            detail['data'][itemkey] = detail['data'][itemkey].round(3)
          end
        end
      end

      result['总分'] = all_score.to_s
      project&.evaluation_model&.levels&.map do |level|
        result['等级'] = level['name'] + '级' if all_score < level['max'] && all_score > level['min']
      end
      result['综合评价平均分'] = result['省工商联'].to_s
      result['自我评价平均分'] = result['自我评价'].to_s
      result['匿名评价平均分'] = result['匿名评价'].to_s
      result['自我评价'] = result['_自我评价']
      result['省工商联'] = result['_省工商联']
      result['匿名评价'] = result['_匿名评价']
      result.delete('_省工商联')
      result.delete('_自我评价')
      result.delete('_匿名评价')
    end
    order_field.insert(0, order_field.pop())
    render json: { ok: true, records: results, order_field: order_field }
  end

  private

  def project_params
    params.require(:project).permit(:name,
                                    :evaluation_model_id,
                                    progress: {},
                                    user_ids: [])
  end

  def set_project
    @project = Project.find(params[:id])
    @project[:project_type] = @project&.evaluation_model.evaluation_type
  end

  def projects_of_current_user
    projects = Project.order_by(created_time: :desc)
    if @current_user.role.include?('省工商联')
      projects
    elsif @current_user.role.include?('市地工商联')
      projects.find_all do |p|
        p.type == '执委评价' || p.users.include?(@current_user)
      end
    else
      projects.find_all { |p| p.users.include?(@current_user) }
    end
  end

  def objects_of_current_user
    role = @current_user[:role]
    unless role.include?('省工商联') ||
           (role.include?('市地工商联') &&
               @project&.evaluation_model&.evaluation_type == '执委评价')
      render json: { ok: false, error: 'dont_have_permission' }, status: :unauthorized
    end

    objects = @project&.users&.only(:name, :company_name, :progress)
    objects = objects.where(address: @current_user[:address]) unless role.include?('省工商联')
    objects.map do |object|
      records = @project&.evaluation_records&.where(evaluated_user: object)
      object[:progress] = {
        self: records&.count { |r| r.type == '自我评价' },
        anonymous: records&.count { |r| r.type == '匿名评价' },
        city: records&.count { |r| r.type == '市地工商联' && r.evaluating_user == @current_user },
        official: records&.count { |r| r.type == '省工商联' }
      }
      object
    end
  end
end
