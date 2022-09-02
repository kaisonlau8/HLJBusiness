class Detail
  include Mongoid::Document

  field :item, type: String
  field :standard, type: String
  field :score, type: Integer

  embedded_in :evaluation
end
