require "yaml"
require "ostruct"

class Config
  attr_reader :local, :remote

  def initialize(yaml_data)
    data = YAML.load(yaml_data)

    @local = OpenStruct.new(
      default_local_db.merge(data.dig("local", "database") || {})
    )

    @remote = {}
    (data["remote"] || {}).each do |env, env_data|
      db_data = default_remote_db.merge(env_data["database"] || {})
      conn_data = default_connection.merge(env_data["connection"] || {})
      custom_cmds = env_data["custom_commands"] || []

      @remote[env.to_sym] = OpenStruct.new(
        database: OpenStruct.new(db_data),
        connection: OpenStruct.new(conn_data),
        custom_commands: custom_cmds
      )
    end
  end

  private

  def default_local_db
    {
      host: "localhost",
      user: "postgres",
      port: "5432"
    }
  end

  def default_remote_db
    {
      port: "5432"
    }
  end

  def default_connection
    {
      type: "ssh",
      ssh_user: "root",
      ssh_port: 22
    }
  end
end
