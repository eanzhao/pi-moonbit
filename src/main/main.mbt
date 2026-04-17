///| pimbt CLI 入口。实际逻辑在 lib/cli 包中，这里只做薄壳转发。
fn main {
  @cli.run_main(@env.args())
}
