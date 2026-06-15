module RemoteDatabaseImporter
  class Operation
    require "remote_database_importer/config"
    require "tty/spinner/multi"

    attr_accessor :config
    attr_accessor :current_environment

    LOG_FILE = "tmp/remote_database_importer.log"

    def initialize
      @config = RemoteDatabaseImporter::Config.new.read_or_create_configfile
    end

    def environments
      config.fetch("environments")
    end

    def select_environment
      if environments.size > 1
        puts "Select the operation environment:"

        environments.map(&:keys).flatten.each_with_index do |env, index|
          puts "#{index} for #{env.capitalize}"
        end
        env = environments[$stdin.gets.chomp.to_i].values[0]
        raise "Environment couldn't be found!" if env.blank?
        @current_environment = env
        return
      end

      @current_environment = environments[0].values[0]
    end

    def import
      select_environment
      time_start = Time.now
      multi_spinner = TTY::Spinner::Multi.new("[:spinner] Import remote DB", format: :dots_3)
      tasks = create_tasks_and_spinners(multi_spinner)

      puts "Be aware, you may get asked for a password for the ssh or db connection"
      tasks.each do |task|
        task[:spinner].auto_spin
        task_execution_was_successful = system(task[:command])
        return "Can't continue, following task failed: #{task[:command]} - checkout the logfile: #{LOG_FILE}" unless task_execution_was_successful
        task[:spinner].stop("... Done!")
      end
      puts seconds_to_human_readable_time(Time.now - time_start)
    end

    private

    def create_tasks_and_spinners(multi_spinner)
      tasks = [
        {name: "Dump remote DB", command: dump_remote_db},
        {name: "Terminate current DB sessions", command: terminate_current_db_sessions},
        {name: "Drop and create local DB", command: drop_and_create_local_db},
        {name: "Restore remote DB", command: restore_db},
        {name: "Remove logfile", command: remove_logfile},
        {name: "Remove dumpfile", command: remove_dumpfile},
        {name: "Custom commands", command: custom_commands}
      ]
      tasks.each.with_index(1) do |task, index|
        task[:spinner] = multi_spinner.register "#{index}/#{tasks.length} :spinner #{task[:name]}"
      end
      tasks
    end

    # terminate local db sessions, otherwise the db can't be dropped
    def terminate_current_db_sessions
      "psql -d #{config.fetch("local_db_name")} -c 'SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();' >> #{LOG_FILE} 2>&1"
    end

    def dump_remote_db
      host = current_environment["connection"]["host"]
      db_name = current_environment["database"]["name"]
      db_user = current_environment["database"]["user"]
      dump_type = current_environment["connection"]["dump_type"]
      ssh_user = current_environment["connection"]["ssh_user"]
      ssh_port = current_environment["connection"]["ssh_port"]
      postgres_port = current_environment["connection"]["postgres_port"]

      if dump_type == "ssh_tunnel"
        "ssh #{ssh_user}@#{host} -p #{ssh_port} 'pg_dump -Fc -U #{db_user} -d #{db_name} -h localhost -C' > #{db_dump_location} 2>> #{LOG_FILE}"
      else
        "pg_dump -Fc 'host=#{host} dbname=#{db_name} user=#{db_user} port=#{postgres_port}' > #{db_dump_location} 2>> #{LOG_FILE}"
      end
    end

    def drop_and_create_local_db
      "rails db:environment:set RAILS_ENV=development >> #{LOG_FILE} 2>&1; rake db:drop db:create >> #{LOG_FILE} 2>&1"
    end

    def restore_db
      "pg_restore --jobs 8 --no-privileges --no-owner --dbname #{config.fetch("local_db_name")} #{db_dump_location} >> #{LOG_FILE} 2>&1"
    end

    def remove_logfile
      "rm #{LOG_FILE}"
    end

    def remove_dumpfile
      "rm #{db_dump_location}"
    end

    def custom_commands
      current_environment["custom_commands"]
    end

    def db_dump_location
      "tmp/#{current_environment["database"]["name"]}.dump"
    end

    def seconds_to_human_readable_time(secs)
      [[60, :seconds], [60, :minutes], [24, :hours], [Float::INFINITY, :days]].map { |count, name|
        if secs > 0
          secs, n = secs.divmod(count)

          "#{n.to_i} #{name}" unless n.to_i == 0
        end
      }.compact.reverse.join(" ")
    end
  end
end
