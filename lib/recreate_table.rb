# RecreateTable

ActiveRecord::ConnectionAdapters::SchemaStatements.module_eval do

  def recreate_table(table, options={})
    new_table = "#{table}_new"
    as = options[:as] || "SELECT * FROM #{table}"

    model = table.to_s.titleize.singularize.constantize
    columns = model.columns.dup
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

      drop_table table

      rename_table new_table, table

      index_definitions.each { |index_definition| execute index_definition }
    end
  end
end

