# 从 core 和 Mooncakes 校验改写的边界

选取了 6 个已合并的 core PR，以及 Mooncakes 上处理响应式状态、解析、前缀树、I/O、排版和字符串的 6 个发布版本。社区样本按注册表 SHA-256 校验。这是按可观察行为选取的样本，不能用于估计生态中的误报率。

## 两个会改变用户程序的建议

**把局部回调移进闭包会导致编译失败。** core 将一个提前返回的遍历改成了短路的 `Array::any`。另一个 PR 却需要把 `Array::any/all` 的循环展开，使 `#locals(f)` 标注能够成立。在 2026-11-20 nightly 上，直接在循环里调用 `p(x)` 可以编译，改成 `xs.any(x => p(x))` 或 `it.find_first(x => p(x))` 都得到 E4163。MoonGrep 现在对需要引入闭包的循环、映射和延迟默认值检查实际回调的绑定。内层重新绑定的同名函数依然可以匹配。[core #3542](https://github.com/moonbitlang/core/pull/3542) · [core #3833](https://github.com/moonbitlang/core/pull/3833)

**载荷相等，订阅通知次数也可能变化。** `mizchi/signals@0.6.1` 的 `src/core_signal.mbt` 第 53–65 行用 `physical_equal` 决定是否传播变更。core 的持久化 HashMap 也专门保留删除缺失键后的对象身份。由此构造的最小例子中，向观察者传入 `r.map(x => x)` 触发一次通知，传入原来的 `r` 触发零次，两个 `Result` 的载荷相等。`Some(42L).bind(x => Some(x))` 也能得到新的包装。Wasm 和 native 的 debug、release 均复现了这两个差异。四条 `Option/Result` 的 map/bind 恒等规则现在要求外层立即消费标签或载荷。整值返回、转交其他函数、通过 `as` 绑定整值时会跳过建议。[Mooncakes 发布包](https://download.mooncakes.io/user/mizchi/signals/0.6.1.zip) · [core #4300](https://github.com/moonbitlang/core/pull/4300)

## 现有规则和后续规则应保留的行为

| 来源 | 容易误判的写法 | 需要保留的行为 |
| --- | --- | --- |
| core JSON 解码 | 把带容量的 `push` 循环统一换成推导式，或删除总会成功的 `guard!` | #3960 的模式绑定让枚举字段可写，直接换成 `let` 在最小例中得到 E4028。#4303 又把嵌套数组解码改回预分配，PR 报告 native 从 137 µs 降至 102 µs。已有推导式规则只接受从空数组字面量开始的累加器。[#3960](https://github.com/moonbitlang/core/pull/3960) · [#4303](https://github.com/moonbitlang/core/pull/4303) |
| core Map | 将 `m.get(k).unwrap_or_else(f)` 合并成 `m.get_or_init(k, f)` | 前者连续缺失两次可以执行两次回调。后者首次执行就写入，第二次命中。回调还可能递归更新同一张表。回归覆盖表内容和回调次数。[#4320](https://github.com/moonbitlang/core/pull/4320) |
| `mizchi/signals@0.6.1` | 把清空队列的循环换成遍历一次快照 | `src/system.mbt` 第 459–463 行每次取出一个回调再执行。执行中的回调可以追加任务。缩小到两个任务后，同一轮必须执行两次。循环条件本身仍可写成 `!queue.is_empty()`。[发布源码](https://download.mooncakes.io/user/mizchi/signals/0.6.1.zip) |
| `mizchi/nom@0.1.2` | 看到可选解析就给内部 `Result` 套用 `to_option` | `src/combinator.mbt` 的 `opt` 仅在可恢复错误时回到原输入。已提交错误和输入不足分别继续传播，成功时保留剩余输入。回归分别检查这四条路径。[发布源码](https://download.mooncakes.io/user/mizchi/nom/0.1.2.zip) |
| `Yoorkin/trie@0.2.10` | 把 `Some(subtree)` 分支当成普通的 `bind` 回调 | `Trie::lookup` 的成功分支携带剩余路径进入下一轮。走完路径之后才读取节点的可选值。测试区分存在的前缀、带值的终点和缺失的边。[Trie 源码](https://assets.mooncakes.io/assets/Yoorkin/trie@0.2.10/trie.mbt.html) |
| `gmlewis/io@0.23.3` | 看到 EOF 就丢弃最后一次读取的结果 | `io.mbt` 的 `read_at_least` 第 299–315 行先累计本次读到的字节，再按总数处理 EOF。同一次读出 2 字节并到达 EOF，请求 2 字节成功，请求 3 字节则是短读。[发布源码](https://download.mooncakes.io/user/gmlewis/io/0.23.3.zip) |
| `moonbit-community/prettyprinter@0.4.11` | 对任意用户类型都把 `a == b` 和 `Compare::compare(a, b) == 0` 互换 | 原版 `Requirement` 的两个 trait 实现对 `Infinite, Infinite` 分别给出 `true` 和 `1`。将这两段实现原样编译后在 wasm 和 native 验证了结果。今后设计比较规则时需要核对实际实现。[固定版本源码](https://github.com/moonbit-community/prettyprinter/blob/45b6ad1a93f69a03c6278340f5c68812e5eb1b13/requirement.mbt#L27-L43) |

正向对照使用 `justjavac/case@0.2.0`。将发布包中的 `src/utils.mbt` 原样放入使用当前清单格式的临时包，真实 IDE 在第 107、113、125 行分别确认大写、小写、数字三处 ASCII 闭区间。这些建议保留了输入类型、边界和对非 ASCII 字符的结果。[固定版本源码](https://github.com/justjavac/moonbit-case/blob/4a55acfa1fdcc878f7952758bea0d8139c0dad27/src/utils.mbt#L104-L126)

## 在本仓库复现

在相同 nightly 上对同一份反例源码运行 `lint`，基线 `d4961e1` 报告 9 处语义建议，修复后剩下队列条件的 1 处。普通结构规则独立输出。复扫使用 52 条内建语义规则，未将选取的旧版社区包添加为依赖。

```sh
moon run --target native . -- lint examples/stdlib-patterns/counterexamples.mbt --target wasm
moon test --target native tests/ide --filter '*counterexamples*'
MOON_WORK=off moon -C examples/stdlib-patterns test --target wasm,native
```

源码和断言是按上述发布版本提炼的最小复现。可以直接观察编译约束、订阅次数、队列顺序、解析位置、容量以及查表副作用。[反例](counterexamples.mbt) · [行为测试](counterexamples_wbtest.mbt)
