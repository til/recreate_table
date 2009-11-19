# RecreateTable

ActiveRecord::ConnectionAdapters::SchemaStatements.module_eval do

  def recreate_table(table, options={})
    old_table = "#{table}_old"
    as = options[:as] || "SELECT * FROM #{old_table}"

    model = table.to_s.titleize.singularize.constantize
    columns = model.columns.dup
    id_sequence = "#{table}_id_seq"

    transaction do

      rename_table table, old_table

      execute "CREATE TABLE #{table} AS (#{as})"

      columns.each do |column|
        if column.primary
          execute "ALTER TABLE #{table} ADD PRIMARY KEY (#{column.name})"
          execute "ALTER TABLE #{table} ALTER COLUMN #{column.name} SET DEFAULT nextval('#{id_sequence}'::regclass)"
          execute "ALTER SEQUENCE #{id_sequence} OWNED BY #{table}.id"
        else
          change_column table, column.name, column.type, { :null => column.null , :default => column.default }
        end
      end
      
      indexes(old_table).each do |index|
        execute "DROP INDEX #{index.name}"
        add_index table, index.columns, :name => index.name, :unique => index.unique
      end

      drop_table old_table
    end
  end
end

