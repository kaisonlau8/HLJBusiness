class Evaluation
  include Mongoid::Document

  field :content, type: String

  embeds_many :details
  embedded_in :evaluation_model
end
