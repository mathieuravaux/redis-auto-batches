guard 'rspec', :version => 2, :cli => "--color --format nested --no-drb", :notification => true do
  watch(%r{^spec/.+_spec\.rb$})
  watch(%r{^lib/(.+)\.rb$})     { |m| "spec/lib/#{m[1]}_spec.rb" }
  watch('spec/spec_helper.rb')  { "spec" }
  watch(%r{spec/support/.+\.rb})  { "spec" }
end

