namespace :graphql do
  desc "Dump SDL to docs/schema.graphql for frontend codegen"
  task dump_schema: :environment do
    schema = BackendSchema.to_definition
    path = Rails.root.join("docs/schema.graphql")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, schema)
    puts "Wrote #{path} (#{schema.bytesize} bytes)"
  end
end
