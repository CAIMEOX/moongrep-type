///|
async fn main {
  @cli.run_cli(@cli.runtime_cli_args(@env.args()), env=@env.get_env_vars())
}
