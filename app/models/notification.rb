class Notification
  include Mongoid::Document

  field :type, type: String
  field :content, type: String
  field :created_at, type: DateTime, default: Time.now
end
