class Record
  include Mongoid::Document

  field :score, type: BigDecimal
  field :files, type: Array
  field :detail_id, type: BSON::ObjectId

  embedded_in :evaluation_record

  def detail
    Detail.find(detail_id)
  end

  def detail=(detail)
    self.detail_id = detail.id
  end
end
