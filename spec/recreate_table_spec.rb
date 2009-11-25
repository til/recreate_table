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
    Foo.reset_column_information

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
    Foo.reset_column_information
    Foo.create!
  end

  it "should allow to add new columns" do
    Foo.connection.recreate_table :foos, :as => "SELECT *, 123 AS baz FROM foos"
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
    Foo.connection.execute "CREATE INDEX index_foos_on_baz_rounded ON foos (round(baz))"
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
  
  it "should retain special indexes" do
    Foo.connection.recreate_table :foos
    Foo.reset_column_information
    
    index_definition = Foo.connection.select_value("SELECT indexdef FROM pg_indexes WHERE indexname='index_foos_on_baz_rounded'")
    
    index_definition.should == "CREATE INDEX index_foos_on_baz_rounded ON foos USING btree (round((baz)::double precision))"
  end
  
  it "should keep of name primary key index" do
    Foo.connection.recreate_table :foos
    
    primary_key_index = Foo.connection.select_value(<<-SQL)
      SELECT c.relname FROM pg_index i
      JOIN pg_class t ON i.indrelid=t.oid
      JOIN pg_class c ON i.indexrelid=c.oid
      WHERE i.indisprimary AND t.relname='foos'
    SQL
    primary_key_index.should == 'foos_pkey'
  end

  it "should remove old primary key index" do
    Foo.connection.recreate_table :foos

    Foo.connection.
      select_value("SELECT COUNT(*) FROM pg_indexes WHERE indexname LIKE '%foos%_pkey'").
      to_i.should == 1
  end

  it "should create indices on new table to minimize downtime" do
    # Works, but don't know how to spec this easily
  end
end


describe "recreate_table with a table name that contains underscores" do

  class FooBar < ActiveRecord::Base; end
  
  before(:each) do
    FooBar.connection.create_table(:foo_bars) do |t|
    end
  end

  it "should not fail" do
    lambda {
      FooBar.connection.recreate_table :foo_bars
    }.should_not raise_error
  end

  it "should constantize table name" do
    RecreateTable::model(:foo_bars).should == FooBar
  end
end


describe "RecreateTable::replace_table_in_index_definition" do
  
  it "should replace original table with new table" do
    RecreateTable::replace_table_in_index_definition(
      "CREATE INDEX foos_user_id ON foos USING btree (user_id)",
      "foos",
      "foos_new"
    ).should == "CREATE INDEX foos_user_id ON foos_new USING btree (user_id)"
  end
end
