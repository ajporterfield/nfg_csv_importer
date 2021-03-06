class NfgCsvImporter::ImportService
  include ActiveModel::Model
  require 'roo'
  require 'roo-xls'

  attr_accessor :type, :file, :imported_by, :imported_for, :errors_list, :import_id

  delegate :class_name, :required_columns, :optional_columns, :column_descriptions, :description, :to => :import_definition

  alias_attribute :import_model, :model
  alias_attribute :import_class_name, :class_name

  def import_definition
    service = ::ImportDefinition.new
    service.imported_for = imported_for
    OpenStruct.new service.send(type)
  end

  def import
    load_and_persist_imported_objects
    generate_errors_csv
  end

  def transaction_id
    @transaction_id ||= SecureRandom.urlsafe_base64
  end

  def headers_valid?
    (all_headers_are_string_type? && header_has_all_required_columns? && unknown_columns.empty?)
  end

  def valid_file_extension?
    %w{.csv .xls .xlsx}.include? file_extension
  end

  def unknown_columns
    stripped_headers - all_valid_columns
  end

  def missing_required_columns
    required_columns - stripped_headers
  end

  def no_of_records
    spreadsheet.last_row - 1
  end

  def no_of_error_records
    errors_list ? errors_list.count : 0
  end

  def header_has_all_required_columns?
    missing_required_columns.empty?
  end

  protected

  def additional_class_attributes(row,object)
  end

  def validate_object(object)
    object.valid?
  end

  private

  def load_and_persist_imported_objects
    self.errors_list = Array.new
    (2..spreadsheet.last_row).map do |i|
      row = Hash[[header, spreadsheet.row(i)].transpose]
      row = strip_data(row)
      # this record lookup conflicts with DM, where the ID field is assumed
      # to be an external id. Also, by including an ID field in the file
      # the user may be updated records they did not intend to
      object = row["id"].present? ? model.find_by_id(row["id"]) : new_model
      set_obj_attributes(row,object)
      additional_class_attributes(row,object)
      persist_valid_record(object, i,row)
    end
  end

  def persist_valid_record(model_obj, index, row)
    NfgCsvImporter::Import.increment_counter(:records_processed,import_id)
    if validate_object(model_obj)
      model_obj.save
      NfgCsvImporter::ImportedRecord.create!(
        imported_by_id: imported_by.id,
        imported_for_id: imported_for.id,
        transaction_id:transaction_id,
        importable_id: model_obj.id,
        importable_type: model_obj.class.table_name,
        action: get_action(model_obj),
      )
    else
      NfgCsvImporter::Import.increment_counter(:number_of_records_with_errors,import_id)
      row['Errors'] = "#{model_obj.errors.full_messages.join(', ')}"
      errors_list << row
    end
  end

  def open_spreadsheet
    file_path = File.exists?(file.path) ? file.path : file.url
    case file_extension
    when ".csv" then Roo::CSV.new(file_path)
    when ".xls" then Roo::Excel.new(file_path, {:packed => nil, :file_warning => :ignore})
    when ".xlsx" then Roo::Excelx.new(file_path, {:packed => nil, :file_warning => :ignore})
    end
  end

  def file_extension
    ".#{file.file.extension}"
  end

  def spreadsheet
    @spreadsheet ||= open_spreadsheet
  end

  def header
    @header ||= spreadsheet.row(1).map(&:strip).map(&:downcase)
  end

  def get_action(record)
    record.new_record? ? "create" : "update"
  end


  def all_headers_are_string_type?
    header.collect{|header| header.is_a?(String) }.all?
  end

  def stripped_headers
    (all_headers_are_string_type? ? header.collect(&:strip) : header )
  end

  def all_valid_columns
    (new_model.attributes.keys + required_columns + optional_columns).uniq!
  end

  def set_obj_attributes(row,object)
    # this requires that the object have a attributes= method, which ActiveModel classes do not
    object.attributes = assign_defaults(striped_attributes(row,object))
  end

  def strip_data(data)
    data.inject({}) { |hash, (key, value)|
      hash[key] = value.is_a?(String) ? value.strip : value
      hash
    }
  end

  def striped_attributes(row,object)
    row.slice( *(object.attributes.keys + import_definition.alias_attributes) )
  end


  def assign_defaults(attributes)
    blank_attributes = attributes.select{|key, value| value.blank? }
    blank_attributes.merge!(defaults(attributes).select { |k| blank_attributes.keys.include?(k) || !attributes.keys.include?(k) })
    attributes.merge(blank_attributes)
  end

  def defaults(attributes)
    import_definition.default_values.inject({}){ |h,(k,v)| h[k] = default_value(v, attributes); h }
  end

  def default_value(v, attributes)
    v.respond_to?(:call) ? v.call(attributes) : v
  end

  def model
    import_definition.class_name.classify.constantize
  end

  def new_model
    new_model = model.new
    # assign values for the mountable's imported for and imported by if the import model responds to them
    new_model.send("#{NfgCsvImporter.configuration.imported_for_field}=", imported_for.id) if new_model.has_attribute?(NfgCsvImporter.configuration.imported_for_field)
    new_model.send("#{NfgCsvImporter.configuration.imported_for_class.downcase}=", imported_for) if new_model.has_attribute?(NfgCsvImporter.configuration.imported_for_class.downcase)
    new_model.send("#{NfgCsvImporter.configuration.imported_by_class.downcase}=", imported_by) if new_model.has_attribute?(NfgCsvImporter.configuration.imported_by_class.downcase)
    new_model
  end

  def generate_errors_csv
    return if errors_list.empty?
    CSV.generate(:col_sep => "\t") do |csv|
      csv << errors_list.first.keys
      errors_list.each do |error_hash|
        csv << error_hash.values
      end
    end
  end
end