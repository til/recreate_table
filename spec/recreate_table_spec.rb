require File.dirname(__FILE__) + '/spec_helper'

describe "The RecreateTable plugin" do
  
  it "should add a command to schema commands" do
    ActiveRecord::Base.connection.should respond_to(:recreate_table)
  end
end


describe "recreate_table" do
  class Foo < ActiveRecord::Base; end

  before(:each) do
    Foo.connection.create_table(:foos) do |t|
      t.integer :bar
      t.integer :baz, :null => false, :default => 0
    end
    
    Foo.create!(:bar => 123)
  end

  it "should have Foos" do
    Foo.count.should == 1
  end

  it "should keep the contents of the table" do
    Foo.connection.recreate_table :foos
    
    Foo.count.should == 1
  end
  
  it "should keep the primary key" do
    Foo.connection.recreate_table :foos

    new = Foo.create!
    new.id.should_not be_nil
  end
  
  it "should allow to insert further rows" do
    Foo.connection.recreate_table :foos

    lambda {
      Foo.create!
      Foo.create!
      Foo.create!
    }.should_not raise_error
  end
  
  it "should keep defaults" do
    Foo.connection.recreate_table :foos
    Foo.reset_column_information

    baz = Foo.columns.find { |c| c.name == 'baz' }

    baz.default.should == 0
  end
  
  it "should allow to create with default" do
    Foo.connection.recreate_table :foos
    Foo.reset_column_information

    new = Foo.create!
    new.baz.should == 0
  end
  
  it "should keep NOT NULL constraint" do
    Foo.connection.recreate_table :foos
    Foo.reset_column_information

    baz = Foo.columns.find { |c| c.name == 'baz' }

    baz.null.should be_false
  end
end


describe "recreate_table with new columns" do
  class Foo < ActiveRecord::Base; end

  before(:each) do
    Foo.connection.create_table(:foos) do |t|
      t.integer :bar
    end
    Foo.create!
  end

  it "should allow to add new columns" do
    Foo.connection.recreate_table :foos, :as => "SELECT *, 123 AS baz FROM foos_old"
    Foo.reset_column_information
    
    Foo.first.baz.should == 123
  end
end


describe "recreate_table with indices" do
  class Foo < ActiveRecord::Base; end

  before(:each) do
    Foo.connection.create_table(:foos) do |t|
      t.integer :bar
      t.integer :baz
    end
    Foo.connection.add_index :foos, :bar
    Foo.connection.add_index :foos, :baz, :unique => true
  end

  it "should recreate the indices" do
    Foo.connection.recreate_table :foos
    Foo.reset_column_information
    
    index = Foo.connection.indexes(:foos).find { |i| i.name == 'index_foos_on_bar' }
    index.should_not be_nil
  end
  
  it "should retain uniqueness of indices" do
    Foo.connection.recreate_table :foos
    Foo.reset_column_information
    
    index = Foo.connection.indexes(:foos).find { |i| i.name == 'index_foos_on_baz' }
    index.unique.should be_true
  end
end
