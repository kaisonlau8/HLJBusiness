class EvaluationRecord
  include Mongoid::Document

  field :type, type: String
  field :files, type: Array
  # field :records, type: Array
  field :anonymous_info, type: String
  field :created_at, type: DateTime, default: Time.now

  embeds_many :records

  belongs_to :project
  belongs_to :evaluated_user, class_name: 'User'
  belongs_to :evaluating_user, class_name: 'User'

  def score(detail_id = nil)
    return records.sum(&:score) if detail_id.nil?

    records.find_by(detail_id: detail_id).score
  end
end
