task :default => [:test, :build, :docs]

desc 'test'
task :test do
  sh "dub test"
end

desc 'build'
task :build do
  sh "dub build"
  sh "cp worker ~/bin/"
end

desc 'docs'
task :docs do
  sh "dub build --build=docs"
end

desc 'format'
task :format do
  sh "find . -name '*.d' | xargs dfmt -i"
end
