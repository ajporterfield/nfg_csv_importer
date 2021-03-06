class User < ActiveRecord::Base
  has_many :imports, class_name: "NfgCsvImporter::Import"

  validates :email, :presence => true, format: /\A.+@.+\Z/
  validates :first_name, presence: true

  def name
    "#{first_name} #{last_name}"
  end
end