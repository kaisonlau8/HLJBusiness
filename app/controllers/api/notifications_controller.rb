class Api::NotificationsController < Api::ApiController
  skip_before_action :header_authorization_verify, only: [:index]
  before_action :need_admin, except: [:index]

  def index
    notifications = Notification.order_by(created_at: :desc)
    unless params[:type].nil?
      notifications = notifications.where(type: params[:type])
    end
    render json: { ok: true, notifications: notifications }
  rescue StandardError
    render json: { ok: false, error: 'get_all_notification_error' }, status: :internal_server_error
  end

  def create
    allowed_types = %w[商会评价 市地工商联评价 执委评价]
    unless allowed_types.include?(notification_params[:type])
      return render json: { ok: false, error: 'invalid_type' }, status: :bad_request
    end

    notification = Notification.create!(notification_params)
    render json: { ok: true, notification: notification }
  end

  def destroy
    Notification.find(params[:id])&.destroy!
    render json: { ok: true }
  rescue StandardError
    render json: { ok: false, error: 'delete_notification_error' }, status: :internal_server_error
  end

  private

  def notification_params
    params.require(:notification).permit(:type, :content)
  end
end
