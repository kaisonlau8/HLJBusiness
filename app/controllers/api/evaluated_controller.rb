class Api::EvaluatedController < Api::ApiController
  before_action :need_admin_or_official
  before_action :need_admin, only: %i[destroy]
  before_action :set_project
  before_action :set_user, only: %i[destroy link score]

  def index
    evaluated = Project.collection.aggregate(
      [
        {
          '$match': {
            '_id': BSON::ObjectId(params[:project_id].to_s)
          }
        },
        {
          '$lookup': {
            'from': 'users',
            'localField': 'users',
            'foreignField': '_id',
            'as': 'user_info'
          }
        },
        {
          '$project': {
            'user_info.password': 0,
            'users': 0
          }
        }
      ]
    )

    render json: { ok: true, evaluated: evaluated }
  rescue StandardError
    render json: { ok: false, error: 'evaluated_query_error' }, status: :internal_server_error
  end

  def sorted
    users = @project.users
    users = users.map do |u|
      { _id: u[:_id],
        company_name: u[:company_name],
        score: u.score_of(@project, params[:detail_id]) }
    end
    users = users.sort_by { |u| u[:score].to_f }.reverse
    render json: { ok: true, users: users }
  end

  def destroy
    @project&.users&.delete(@evaluated_user)
    render json: { ok: true }
  end

  def link
    payload = {
      project_id: params[:project_id], # project_id
      evaluated_user_id: params[:id], # Project.user_ids[n]
      evaluated_user_company_name: CGI.escape(@evaluated_user[:company_name])
    }

    token = JWT.encode payload, Rails.configuration.global['jwt_key'], 'HS256'

    render json: { ok: true, token: token }
  rescue Mongoid::Errors::DocumentNotFound
    render json: { ok: false, error: 'project_id_not_found' }, status: :internal_server_error
  rescue StandardError
    render json: { ok: false, error: 'link_generate_error' }, status: :internal_server_error
  end

  def score
    score = @evaluated_user.score_of(@project)
    level = @project&.level_by_score(score)
    render json: { ok: true, score: score, level: level }
  end

  private

  def set_project
    unless params[:project_id]
      return render json: { ok: false, error: 'project_no_params' }, status: :bad_request
    end

    @project = Project.find(params[:project_id])
  end

  def set_user
    unless @project&.user_ids&.include? BSON::ObjectId(params[:id])
      render json: { ok: false, error: 'evaluated_id_not_found_in_project' }, status: :bad_request
    end

    @evaluated_user = User.find(params[:id])
  end
end
