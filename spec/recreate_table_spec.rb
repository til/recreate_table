require File.dirname(__FILE__) + '/spec_helper'


describe RecreateTable, "prepare" do
  class Customer < ActiveRecord::Base; end

  def connection(*args)
    ActiveRecord::Base.connection
  end

  before(:each) do
    connection.create_table(:customers) do |t|
      t.integer :bar
    end
    connection.add_index :customers, :bar

    Customer.reset_column_information
    Customer.create!
    Customer.create!
    
    RecreateTable.prepare(:customers, :as => "SELECT *, 123 AS baz FROM customers")
  end

  it "should create a table with '_new' appended" do
    connection.select_value(
      "SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='customers_new'"
    ).should_not be_nil
  end
  
  it "should copy all values" do
    connection.select_value("SELECT count(*) FROM customers_new").to_i.should == 2
  end
  
  it "should create primary key" do
    indexes = connection.select_values(<<-SQL)
      SELECT c.relname FROM pg_index i
      JOIN pg_class t ON i.indrelid=t.oid
      JOIN pg_class c ON i.indexrelid=c.oid
      WHERE t.relname='customers_new' AND i.indisprimary
    SQL

    indexes.should include("customers_new_pkey")
  end

  it "should create indexes" do
    indexes = connection.select_values(<<-SQL)
      SELECT c.relname FROM pg_index i
      JOIN pg_class t ON i.indrelid=t.oid
      JOIN pg_class c ON i.indexrelid=c.oid
      WHERE t.relname='customers_new'
    SQL

    indexes.should include("index_customers_new_on_bar")
  end
end


describe RecreateTable, "prepare with not null column" do
  def connection(*args)
    ActiveRecord::Base.connection
  end

  class Foo < ActiveRecord::Base; end

  before(:each) do
    Foo.connection.create_table(:foos) do |t|
      t.integer :baz, :null => false
    end
  end

  it "should keep NOT NULL constraint" do
    RecreateTable.prepare :foos
    RecreateTable.activate :foos
    Foo.reset_column_information

    baz = Foo.columns.find { |c| c.name == 'baz' }

    baz.null.should be_false
  end
end


describe RecreateTable, "prepare with id column" do
  def connection(*args)
    ActiveRecord::Base.connection
  end

  class Customer < ActiveRecord::Base; end

  before(:each) do
    Customer.connection.create_table(:customers) do |t|
    end
  end

  it "should keep sequence" do
    RecreateTable.prepare :customers
    RecreateTable.activate :customers
    Customer.reset_column_information

    Customer.create!
    Customer.create!
    Customer.first.id.should_not be_nil
  end
end


describe RecreateTable, "activate" do
  def connection(*args)
    ActiveRecord::Base.connection
  end

  def indexes(table)
    connection.select_values(<<-SQL)
      SELECT c.relname FROM pg_index i
      JOIN pg_class t ON i.indrelid=t.oid
      JOIN pg_class c ON i.indexrelid=c.oid
      WHERE t.relname='#{table}'
    SQL
  end

  before(:each) do
    connection.execute("CREATE TABLE customers (id serial primary key, foo integer)")
    connection.add_index :customers, :foo
    connection.execute("INSERT INTO customers (foo) VALUES (111)")


    connection.execute("CREATE TABLE customers_new (id serial primary key, bar integer)")
    connection.add_index :customers_new, :bar
    connection.execute("INSERT INTO customers_new (bar) VALUES (222)")
  end

  it "should rename new table to original" do
    RecreateTable.activate(:customers)
    
    connection.select_value("SELECT bar FROM customers").to_i.should == 222
  end
  
  it "should rename indexes on new table" do
    RecreateTable.activate(:customers)

    indexes('customers').should include('customers_pkey')
    indexes('customers').should include('index_customers_on_bar')
  end

  it "should rename original table to _old" do
    RecreateTable.activate(:customers)
    
    connection.select_value("SELECT foo FROM customers_old").to_i.should == 111
  end
  
  it "should rename indexes on old table" do
    RecreateTable.activate(:customers)

    indexes('customers_old').should include('customers_old_pkey')
    indexes('customers_old').should include('index_customers_old_on_foo')
  end
  
  it "should rename new sequence" do
    RecreateTable.activate(:customers)

    connection.select_value("select pg_get_serial_sequence('customers', 'id')").
      should == "public.customers_id_seq"
  end
  
  it "should rename old sequence" do
    RecreateTable.activate(:customers)

    connection.select_value("select pg_get_serial_sequence('customers_old', 'id')").
      should == "public.customers_old_id_seq"
  end
end


describe RecreateTable, "cleanup" do
  def connection(*args)
    ActiveRecord::Base.connection
  end

  before(:each) do
    connection.create_table :customers_old do |t|
    end
  end
  
  it "should remove the old table" do
    RecreateTable.cleanup(:customers)
    
    connection.select_value(
      "SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='customers_old'"
    ).should be_nil
  end
end
