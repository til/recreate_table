# RecreateTable

ActiveRecord::ConnectionAdapters::SchemaStatements.module_eval do

  def recreate_table(table, options={})
    new_table = "#{table}_new"
    as = options[:as] || "SELECT * FROM #{table}"

    columns = RecreateTable::model(table).columns.dup
    id_sequence = "#{table}_id_seq"

    transaction do

      execute "CREATE TABLE #{new_table} AS (#{as}) WITH NO DATA"

      columns.each do |column|
        if column.primary
          execute "ALTER TABLE #{new_table} ADD PRIMARY KEY (#{column.name})"
          execute "ALTER TABLE #{new_table} ALTER COLUMN #{column.name} SET DEFAULT nextval('#{id_sequence}'::regclass)"
          execute "ALTER SEQUENCE #{id_sequence} OWNED BY #{new_table}.id"
        else
          change_column new_table, column.name, column.type, { :null => column.null , :default => column.default }
        end
      end
      
      execute "INSERT INTO #{new_table} (#{as})"


      index_definitions = select_values("SELECT indexdef FROM pg_indexes WHERE tablename='#{table}'")
      index_names = select_values("SELECT indexname FROM pg_indexes WHERE tablename='#{table}'")

      # Rename old indices to make way for similarly named indices on
      # new table
      index_names.each do |index_name|
        execute("ALTER INDEX #{index_name} RENAME TO #{index_name}_old")
      end

      # Create indices on new table
      index_definitions.each do |index_definition| 
        execute(RecreateTable::replace_table_in_index_definition(
            index_definition,
            table,
            new_table))
      end

      drop_table table

      rename_table new_table, table
    end
  end
end


module RecreateTable
  
  def self.model(table)
    table.to_s.singularize.camelize.constantize
  end
  
  def self.replace_table_in_index_definition(index_definition, table, new_table)
    index_definition.gsub(/ON #{table}/, "ON #{new_table}")
  end
end
