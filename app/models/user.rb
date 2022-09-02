class User
  include Mongoid::Document
  include ActiveModel::SecurePassword

  field :name, type: String
  field :password_digest, type: String
  field :is_admin, type: Boolean
  field :role, type: Array
  field :company_name, type: String
  field :user_uuid, type: String
  field :address, type: BSON::Binary

  has_secure_password
  has_and_belongs_to_many :projects

  def self.login_verify(name, password)
    find_by(name: name)&.authenticate(password)
  rescue StandardError
    nil
  end

  def self.create_jwt_by_verified(name, user_uuid)
    payload = {
      uuid: user_uuid,
      name: name,
      expire_at: Time.now.utc + 1.day
    }
    # No Exception catch
    JWT.encode payload, Rails.configuration.global['jwt_key'], 'HS256'
  end

  def self.admin_by_payload?(payload)
    user_doc = where(name: payload['name']).first
    return true if user_doc[:is_admin]
  end

  def score_of(project, detail_id = nil)
    scores = scores_of_all_types(project, detail_id)
    role_percentages_map = generate_role_percentages_map(project)
    sum_score = 0
    scores.each do |k, s|
      sum_score += s * (role_percentages_map[k] || 0)
    end
    sum_score
  end

  private

  def scores_of_all_types(project, detail_id)
    project_evaluation_records = EvaluationRecord
                                 .where(evaluated_user: self,
                                        project: project)
    scores = {}
    project_evaluation_records.each do |r|
      scores[r.type] ||= { count: 0, score: 0 }
      scores[r.type][:count] += 1
      scores[r.type][:score] += r.score(detail_id)
    end
    Hash[scores.map do |k, s|
      [k, s[:score] / s[:count]]
    end]
  end

  def generate_role_percentages_map(project)
    role_percentages_array = project.evaluation_model.role_percentages
    map = {}
    role_percentages_array.each do |r|
      map[r[:role]] = BigDecimal(r[:percentage])
    end
    map
  end
end
