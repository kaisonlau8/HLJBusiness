class Api::ApiController < ApplicationController
  before_action :current_user, except: [:login]
  before_action :header_authorization_verify, except: [:login]

  def login
    user_doc = User.login_verify(params[:name], params[:password])
    unless user_doc
      return render json: { ok: false, error: 'login_failure' }, status: :forbidden
    end

    token = User.create_jwt_by_verified(user_doc[:name], user_doc[:user_uuid])
    render json: { ok: true, token: token }
  rescue StandardError
    render json: { ok: false, error: 'login_failure' }, status: :internal_server_error
  end

  def verify
    render json: { ok: true }
  end

  def s3
    project = Project.find(params[:project_id])
    unless project&.users&.include? @current_user
      return render json: { ok: false, error: 'user_no_permissions' }, status: :unauthorized
    end

    extension_name = params[:file_name].split('.')&.last&.downcase

    file_type_correctness =
      case extension_name
      # when 'jpg'
      #   params[:file_content_type] == 'image/jpeg'
      # when 'png'
      #   params[:file_content_type] == 'image/png'
      # when 'doc'
      #   params[:file_content_type] == 'application/msword'
      # when 'docx'
      #   params[:file_content_type] == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      # when 'xls'
      #   params[:file_content_type] == 'application/vnd.ms-excel'
      # when 'xlsx'
      #   params[:file_content_type] == 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      when 'pdf'
        params[:file_content_type] == 'application/pdf'
      # when 'zip'
      #   params[:file_content_type] == 'application/zip'
      # when 'mp4'
      #   params[:file_content_type] == 'video/mpeg4'
      # when 'mp3'
      #   params[:file_content_type] == 'audio/mp3'
      else
        false
      end

    unless file_type_correctness
      return render json: { ok: false, error: 'file_type_error' }, status: :bad_request
    end

    credentials = Aws::Credentials.new(
      Rails.configuration.global['s3'][:access_key_id],
      Rails.configuration.global['s3'][:secret_access_key]
    )

    s3_presigned_post = Aws::S3::PresignedPost.new(
      credentials.credentials,
      Rails.configuration.global['s3'][:region],
      Rails.configuration.global['s3'][:bucket].to_s,
      {
        key: Digest::UUID.uuid_v4.to_s[24, 12] + '-' + params[:file_name].to_s,
        content_type: params[:file_content_type],
        content_length_range: 0..20.megabytes, # 20MB
        url: Rails.configuration.global['s3'][:endpoint].to_s + Rails.configuration.global['s3'][:bucket].to_s
      }
    )

    fields = s3_presigned_post.fields
    fields['bucket'] = Rails.configuration.global['s3'][:bucket].to_s
    render json: { ok: true, url: s3_presigned_post.url, fields: fields }
  end

  def s3_get_object
    s3_signer = Aws::S3::Presigner.new
    url, headers = s3_signer.presigned_request(
      :get_object,
      bucket: Rails.configuration.global['s3'][:bucket].to_s,
      key: params[:file_key]
    )
    render json: { ok: true, url: url, headers: headers }
  rescue StandardError
    render json: { ok: false, error: 'get_file_error' }, status: :internal_server_error
  end

  private

  def header_authorization_verify
    return unless @current_user.nil?

    render json: { ok: false, error: 'token_invalid' }, status: :forbidden
  end

  def current_user
    if request.headers['Authorization']&.start_with?('Bearer')
      jwt_token = request.headers['Authorization'].split&.last
      payload = JWT.decode(jwt_token,
                           Rails.configuration.global['jwt_key'],
                           true, { algorithm: 'HS256' })
      @current_user ||= User.without(:password_digest)
                            .where(user_uuid: payload.first['uuid'])&.first
    end
  rescue JWT::ExpiredSignature, JWT::VerificationError, JWT::DecodeError
    nil
  end

  def admin?
    @current_user[:is_admin]
  end

  def official?
    @current_user[:role].include?('省工商联')
  end

  def need_admin
    return if admin?

    render json: { ok: false, error: 'permission_denied' }, status: :unauthorized
  end

  def need_admin_or_official
    return if admin? || official?

    render json: { ok: false, error: 'permission_denied_admin_or_leader' }, status: :unauthorized
  end
end
