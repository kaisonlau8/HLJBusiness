class Project
  include Mongoid::Document
  include AASM

  field :name, type: String
  field :status, default: :open
  aasm no_direct_assignment: true, column: :status do
    state :open, initial: true
    state :review, :complete
    event :switch_review do
      transitions from: :open, to: :review
      transitions from: :review, to: :open
    end
    event :switch_complete do
      transitions from: :review, to: :complete
      transitions from: :complete, to: :review
    end
  end
  field :created_time, type: DateTime, default: Time.now

  has_and_belongs_to_many :users
  has_many :evaluation_records
  belongs_to :evaluation_model

  def type
    evaluation_model.evaluation_type
  end

  def level_by_score(score)
    evaluation_model.level_by_score(score)
  end
end
