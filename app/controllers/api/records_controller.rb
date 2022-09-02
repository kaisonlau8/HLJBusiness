class Api::RecordsController < Api::ApiController
  skip_before_action :header_authorization_verify, only: [:create]
  before_action :set_record, only: %i[show update destroy]
  before_action :set_anonymous_user, only: [:create]
  before_action :check_self_evaluation, only: [:create]
  before_action :need_admin_or_official, only: [:index]
  before_action :need_admin_or_official_or_self, only: %i[show update destroy]
  before_action :need_open, only: [:update]

  def index
    records = if params[:evaluated_id]
                EvaluationRecord.where(
                  evaluated_user_id: params[:evaluated_id],
                  project_id: params[:project_id]
                )
              elsif params[:project_id]
                Project.find(params[:project_id])&.evaluation_records
              else
                EvaluationRecord.all
              end
    render json: { ok: true, records: records }
  end

  def show
    render json: { ok: true, record: @record }
  end

  def create
    record = EvaluationRecord.create!(record_params)
    render json: { ok: true, record: record }
  end

  def update
    record = @record.update!(record_params)
    render json: { ok: true, record: record }
  end

  def destroy
    @record.destroy!
    render json: { ok: true }
  end

  private

  def record_params
    result = params.require(:record)
                   .permit(:evaluated_user_id,
                           :anonymous_info,
                           files: %i[name url type status],
                           records: [:detail_id, :score,
                                     files: %i[name url type]])
    result[:evaluating_user] = @current_user
    result[:project_id] = params.require(:project_id)
    result[:type] =
      if @current_user == User.without(:password_digest).find('5ece0c2c58d2cc1d6950371d')
        '匿名评价'
      elsif @current_user[:_id] == BSON::ObjectId(result[:evaluated_user_id])
        '自我评价'
      elsif @current_user[:role].include?('省工商联')
        '省工商联'
      elsif @current_user[:role].include?('市地工商联')
        '市地工商联'
      end
    result
  end

  def set_record
    @record =
      if params[:id]
        EvaluationRecord.find(params[:id])
      elsif params[:evaluated_id]
        EvaluationRecord.find_by(
          project_id: params[:project_id],
          evaluated_user_id: params[:evaluated_id],
          type: '自我评价'
        )
      end
  end

  def need_open
    # open状态下自己可修改
    project_id = params.require(:project_id)
    unless Project.find(project_id)&.open?
      return render json: { ok: false, error: 'project_expired' }, status: :conflict
    end

    return nil if @current_user[:_id] == @record[:evaluating_user_id]

    render json: { ok: false, error: 'permission_denied' }, status: :unauthorized
  end

  def need_admin_or_official_or_self
    # open状态下可查看,admin可修改所有（admin改先不做）
    if admin? || official? ||
       @current_user[:_id] == @record[:evaluating_user_id] ||
       (@current_user[:role].include?('市地工商联') &&
        @current_user[:address] == @record.evaluated_user.address)
      return nil
    end

    render json: { ok: false, error: 'permission_denied' }, status: :unauthorized
  end

  def set_anonymous_user
    jwt_token = params[:token]
    return nil if jwt_token.nil?

    payload = JWT.decode(jwt_token, Rails.configuration.global['jwt_key'],
                         true, { algorithm: 'HS256' }).first
    unless payload['project_id'] == params[:project_id]
      return render json: { ok: false, error: 'wrong_project_id' }, status: :unauthorized
    end

    params[:record][:evaluated_user_id] = payload['evaluated_user_id']
    @current_user = User.without(:password_digest).find('5ece0c2c58d2cc1d6950371d')
  rescue JWT::ExpiredSignature, JWT::VerificationError, JWT::DecodeError
    render json: { ok: false, error: 'wrong_token' }, status: :forbidden
  end

  def check_self_evaluation
    return nil unless record_params[:type] == '自我评价'

    record = EvaluationRecord.where(
      project_id: record_params[:project_id],
      evaluated_user_id: record_params[:evaluated_user_id],
      type: '自我评价'
    )
    return nil unless record.exists?

    render json: { ok: false, error: 'self_evaluation_existed' }, status: :conflict
  end
end
