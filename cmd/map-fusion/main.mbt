///|
/// Compatibility entrypoint; parsing, output, and errors use the main CLI.
async fn main {
  @cli.run_cli(
    ["map-fusion", ..@cli.runtime_cli_args(@env.args())],
    env=@env.get_env_vars(),
  )
}
