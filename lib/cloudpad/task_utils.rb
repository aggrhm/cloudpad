module Cloudpad
  module TaskUtils

    def manifests_path
      File.join(Dir.pwd, "manifests")
    end
    def context_path
      File.join(Dir.pwd, "context")
    end
    def cloud_path
      File.join(Dir.pwd, "config", "cloud")
    end
    def repos_path
      File.join(context_path, "src")
    end

    def prompt(question)
      $stdout.print "> #{question}: ".yellow
      return $stdin.gets.chomp
    end

    def build_template_file(name)
      ERB.new(File.read(name)).result(binding)
    end

    def clear_cache
      "RUN echo \"#{Time.now.to_s}\""
    end

    def image_opts
      fetch(:images)[fetch(:building_image)]
    end

    def building_image?(img)
      fetch(:building_image) == img
    end

    ## on host

    def process_running?(name)
      ret = capture("ps -ef | grep #{name} | grep -v \"grep\"")
      return ret.strip.length > 0
    end

  end
end

