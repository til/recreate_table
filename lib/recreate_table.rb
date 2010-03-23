class RecreateTable
  
  def self.prepare(table, options={})
    new_table = "#{table}_new"
    as = options[:as] || "SELECT * FROM #{table}"

    connection.transaction do
      connection.execute "CREATE TABLE #{new_table} AS (#{as}) WITH NO DATA"

      columns = model(table).columns.dup

      columns.each do |column|
        if column.primary
          connection.execute "ALTER TABLE #{new_table} ADD PRIMARY KEY (#{column.name})"
        else
          connection.change_column new_table, column.name, column.type, { :null => column.null , :default => column.default }
        end
      end

      connection.execute "INSERT INTO #{new_table} (#{as})"
      
      # Simply assume a rails-style id column and sequence
      connection.execute <<-SQL
        CREATE SEQUENCE #{new_table}_id_seq;
        SELECT setval('#{new_table}_id_seq', nextval('#{table}_id_seq'));
        ALTER TABLE #{new_table} ALTER COLUMN id SET DEFAULT nextval('#{new_table}_id_seq');
        ALTER SEQUENCE #{new_table}_id_seq OWNED BY #{new_table}.id;
      SQL

      index_definitions = connection.select_values(<<-SQL)
        SELECT indexdef FROM pg_indexes 
        WHERE tablename='#{table}' AND NOT indexname LIKE '%_pkey'
      SQL
      index_definitions.each do |index_definition|
        connection.execute(index_definition.gsub(table.to_s, new_table.to_s))
      end
    end    
  end

  def self.activate(table)
    connection.transaction do
      rename_table(table, "#{table}_old")
      rename_table("#{table}_new", table)
    end
  end

  def self.cleanup(table)
    connection.drop_table("#{table}_old")
  end

  def self.rename_table(old_name, new_name)
    connection.rename_table old_name, new_name
    
    connection.execute("ALTER SEQUENCE #{old_name}_id_seq RENAME TO #{new_name}_id_seq")

    connection.select_values(
      "SELECT indexname FROM pg_indexes WHERE tablename='#{new_name}'"
    ).each do |index_name|
      connection.execute(
        "ALTER INDEX #{index_name} RENAME TO #{index_name.gsub(old_name.to_s, new_name.to_s)}")
    end
  end

  def self.connection
    ActiveRecord::Base.connection
  end

  def self.model(table)
    table.to_s.singularize.camelize.constantize
  end
end
