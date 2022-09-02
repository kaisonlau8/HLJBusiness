class EvaluationModel
  include Mongoid::Document

  field :name, type: String
  field :evaluation_type, type: String
  # field :evaluations, type: Array
  field :levels, type: Array
  field :role_percentages, type: Array # 占比
  field :created_at, type: DateTime, default: Time.now

  embeds_many :evaluations

  has_many :projects

  def self.check_evaluation_type(evaluation_type)
    where(evaluation_type: evaluation_type).exists?
  end

  def level_by_score(score)
    level = levels.find { |l| (l[:min]..l[:max]).include?(score) }
    level[:name]
  end
end
