class Api::UsersController < Api::ApiController
  before_action :need_admin, only: [:index]

  def index
    all_user = User.all.without(:password_digest)
    render json: { ok: true, users: all_user }
  rescue StandardError
    render json: { ok: false, error: 'get_all_user_error' }, status: :internal_server_error
  end

  def show
    render json: { ok: true, user_info: @current_user }
  rescue StandardError
    render json: { ok: false, error: 'get_user_info_error' }, status: :internal_server_error
  end
end
