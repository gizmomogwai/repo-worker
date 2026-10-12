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

desc "Regenerate dub-lock.json from dub.selections.json (run after changing dependencies)"
file "dub-lock.json" => ["dub.selections.json"] do
  sh "nix run nixpkgs#dub-to-nix > dub-lock.json"
end
namespace :nix do
  desc "Lock dub packages"
  task :lock => ["dub-lock.json"]

  desc "Build the flake"
  task :build do
    sh "nix build -L .#default"
  end

  desc "Build the flake and run the resulting binary"
  task test: :build do
    sh "./result/bin/worker --help"
  end

  desc "Update flake.lock"
  task :update do
    sh "nix flake update"
  end
end
