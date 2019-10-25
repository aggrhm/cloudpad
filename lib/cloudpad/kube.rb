module Cloudpad

  class KubeSpec < ConfigElement

    def self.apply_specs!(specs)
      c = Cloudpad.context
      comp_files = comps.collect{|opts| opts[:build_file] }
      args = comp_files.collect{|f| "-f #{f}"}.join(" ")
      sh "#{c.kubecmd} apply #{args}"
    end

    def prepare_options
      opts = @options
      ctx = @context
      opts[:name] = id
      opts[:groups] ||= [id]
      opts[:images] ||= []
      opts[:containers] ||= []
      opts[:file_name] ||= id
      opts[:file_subdir] ||= ""
      opts[:env] ||= {}
      fp = File.join(ctx.kube_path, opts[:file_subdir], opts[:file_name])
      [".yml", ".yml.rb"].each do |ext|
        file = fp + ext
        if File.exists?(file)
          opts[:file] = file
          break
        end
      end
      if opts[:file].blank?
        raise "Kube config file could not be found."
      end
      opts[:build_file] = File.join(ctx.build_kube_path, opts[:file_subdir], "#{opts[:id]}.yml")
    end
    def images
      (self[:images] || []).collect{|id| ctx.images[id]}.compact
    end
    def groups
      (self[:groups] || []).collect{|id| ctx.groups[id]}.compact
    end
    def full_env
      env = self.groups.reduce({}){|res, g| res.merge(g[:env] || {})}
      env.merge(self[:env])
    end
    def containers
      ret = self[:containers].collect {|copts| @options.merge(copts)}
      ret = [@options] if ret.length == 0
      ret.each do |copts|
        if copts[:full_command].is_a?(String)
          cps = copts[:full_command].split(" ")
          copts[:command] = [cps[0]]
          copts[:args] = cps[1..-1]
        end
      end
    end

    def build_spec!
      ctx = @context
      ctx.set :building_spec, self
      # check if tag is known for images
      self.images.each do |img|
        if img[:tag].blank?
          raise "Image #{img[:id]} does not have a known tag set."
        end
      end
      puts "Building kube spec file #{self[:build_file]}"
      ctx.write_template_file(self[:file], self[:build_file])
      ctx.set :building_spec, nil
    end
  end

  class Component < KubeSpec
    def self.map
      Cloudpad.context.fetch(:components)
    end
    def replicas
      r = self[:replicas]
      r.nil? ? 1 : r
    end
  end

  class Job < KubeSpec

    def self.map
      Cloudpad.context.fetch(:jobs)
    end

    def run!
      c = Cloudpad.context
      of = self[:build_file]
      jd = YAML.load_file(of).with_indifferent_access
      jname = jd[:metadata][:name]

      puts "Running job #{jname}..."
      # delete job first
      sh "#{c.kubecmd} delete job #{jname} --ignore-not-found=true"
      sh "#{c.kubecmd} apply -f #{of}"
      puts "Waiting for job".yellow
      loop do
        js = JSON.parse(`#{c.kubecmd} get job/#{jname} -o json`)
        if js['status']['failed'].to_i > 0
          raise "Job did not successfully finish.".red
        end
        if js['status']['succeeded'].to_i >= js['spec']['completions'].to_i
          puts "Job completed successfully.".green
          break
        end
        sleep 1
      end

    end
  end

end
