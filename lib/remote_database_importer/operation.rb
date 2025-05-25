require "remote_database_importer/config"
require "remote_database_importer/utils"
require "tty/spinner/multi"

module RemoteDatabaseImporter
  class Operation
    Command = Struct.new(:name, :command, :spinner)
    LOG_FILE = "tmp/remote_database_importer.log"

    def initialize
      @config = RemoteDatabaseImporter::Config.new.read_or_create_configfile
    end

    def import
      @current_environment = select_environment
      import_start_time = Time.now
      multi_spinner = TTY::Spinner::Multi.new("[:spinner] Import remote DB", format: :dots_3)
      tasks = create_tasks_and_spinners(multi_spinner)

      print_command_previews
      puts "Are you OK with that? (y/n)"
      answer = $stdin.gets.chomp.downcase
      return "Aborted by user!" unless answer.downcase == "y"

      puts
      puts "Be aware, you may get asked for a password for the ssh or db connection"
      execute_commands
      puts seconds_to_human_readable_time(Time.now - import_start_time)
    end

    private

    def select_environment
      if environments.size > 1
        puts "Select the operation environment:"

        environments.map(&:keys).flatten.each_with_index do |env, index|
          puts "#{index} for #{env.capitalize}"
        end
        env = environments[$stdin.gets.chomp.to_i].values[0]
        raise "Environment couldn't be found!" if env.blank?
        return env
      end

      environments[0].values[0]
    end

    def print_command_previews
      puts "The following tasks will be executed:"
      tasks.each do |task|
        puts "- #{task.name} (#{task.command})"
      end
    end

    def execute_commands
      tasks.each do |task|
        task.spinner.auto_spin
        task_execution_was_successful = system(task.command)
        unless task_execution_was_successful
          return "Can't continue, following task failed: #{task.command} - checkout the logfile: #{LOG_FILE}"
        end
        task.spinner.stop("... Done!")
      end
    end

    def create_tasks_and_spinners(multi_spinner)
      tasks = [
        Command.new("Dump remote DB", dump_remote_db),
        Command.new("Terminate current DB sessions", terminate_current_db_sessions),
        Command.new("Drop and create local DB", drop_and_create_local_db),
        Command.new("Restore remote DB", restore_db),
        Command.new("Remove logfile", remove_logfile),
        Command.new("Remove dumpfile", remove_dumpfile),
        Command.new("Custom commands", custom_commands)
      ]
      tasks.each.with_index(1) do |task, index|
        task.spinner = multi_spinner.register("#{index}/#{tasks.length} :spinner #{task.name}")
      end
      tasks
    end

    # terminate local db sessions, otherwise the db might can't be dropped
    def terminate_current_db_sessions
      "psql -d #{@config.fetch("local_db_name")} -c 'SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();' > #{LOG_FILE}"
    end

    def dump_remote_db
      host = @current_environment["connection"]["host"]
      db_host = @current_environment["database"]["host"] || "localhost"
      db_name = @current_environment["database"]["name"]
      db_user = @current_environment["database"]["user"]
      dump_type = @current_environment["connection"]["dump_type"]
      ssh_user = @current_environment["connection"]["ssh_user"]
      ssh_port = @current_environment["connection"]["ssh_port"]
      postgres_port = @current_environment["connection"]["postgres_port"]

      if dump_type == "ssh_tunnel"
        "ssh #{ssh_user}@#{host} -p #{ssh_port} 'pg_dump -Fc -U #{db_user} -d #{db_name} -h #{db_host} -p #{postgres_port} -C' > #{db_dump_path}"
      else
        "pg_dump -Fc 'host=#{host} dbname=#{db_name} user=#{db_user} port=#{postgres_port}' > #{db_dump_path}"
      end
    end

    def drop_and_create_local_db
      "rails db:environment:set RAILS_ENV=development; rake db:drop db:create > #{LOG_FILE}"
    end

    def restore_db
      "pg_restore --jobs 8 --no-privileges --no-owner --dbname #{@config.fetch("local_db_name")} #{db_dump_path}"
    end

    def remove_logfile
      "rm #{LOG_FILE}"
    end

    def remove_dumpfile
      "rm #{db_dump_path}"
    end

    def custom_commands
      @current_environment["custom_commands"]
    end

    def db_dump_path
      @_db_dump_path ||= "tmp/#{@current_environment["database"]["name"]}.dump"
    end

    def environments
      @_environments ||= @config.fetch("environments")
    end
  end
end
