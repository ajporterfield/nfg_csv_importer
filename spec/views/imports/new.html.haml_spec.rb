require 'rails_helper'

describe "imports/new.html.haml" do
  before do
    view.stubs(:imported_for).returns(entity)
    assign(:import, import)
    view.stubs(:import_type).returns(import.import_type)
    render template: 'nfg_csv_importer/imports/new'
  end

  let(:entity) { create(:entity) }
  let(:import) { FactoryGirl.build(:import, imported_for:entity)}

  it "should contain form with file input" do
    within("form") do |form_element|
      expect(form_element).to have_xpath("//input[@type='file']")
    end
  end

  it "should list required fields" do
    import.required_columns.each do |field|
      within("#required_fields") do |field_div|
        expect(field_div).to have_text(field)
      end
    end
  end

  it "should display a description" do
    expect(rendered).to match(/#{import.description}/)
  end

end