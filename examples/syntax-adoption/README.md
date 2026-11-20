# 社区代码里还可以用上哪些 MoonBit 语法

最值得 MoonGrep 先做的是**循环头解构**，其次是**同一标量上的字面量备选模式**。两类写法在多个独立包中重复出现。条件展开、流式插值以及用于固定字节布局的模式也有很好的实例，但能否建议改写，更依赖具体的求值顺序和输入契约。

对照了 15 个已合并的 core PR。2026-11-20 从 Mooncakes 索引 `49bbeeea0e60b3deee82dcebd21f478ca57b455c` 定向选择了 17 个与首轮不同的包，涉及解析、编码、字体、UI、Git、集合和符号运算。每个包取当时未撤回的最高正式版本，按注册表 SHA-256 校验。结构扫描使用 MoonGrep `7488350` 与 `moonbitlang/parser@0.4.9`。编译验证使用 `v0.10.22+c5d6f7c27-nightly`。迁移到这些语法还取决于库承诺支持的最低编译器版本。[样本版本与校验和](corpus.tsv)

## 优先做成规则的两种写法

| 写法 | 真实代码和建议 | 建议所需的证据 |
| --- | --- | --- |
| 在 `for` 头部解构 | Rabbita 0.17.0 的 `stores.mbt:29` 先写 `for key, sub in new_subs`，第一句再写 `let (payload, loader) = sub`。可以直接写 `for key, (payload, loader) in new_subs`。字体库也有 `for (cp, gid) in ...` 的单元素版本。[Rabbita 源码](https://github.com/moonbit-community/rabbita/blob/4a20586a080bed3d557cbffd698cc26e3a496fd8/rabbita/internal/runtime/stores.mbt#L29-L34) · [moon_skrifa 源码，第 203 行](https://assets.mooncakes.io/assets/Milky2018/moon_skrifa@0.2.0/outline/autohint.mbt.html) · [core #4440](https://github.com/moonbitlang/core/pull/4440) | 首句解构的是本次循环绑定，模式总能匹配，后续也用不到原绑定。保留一个元素与双元素迭代的区别。cmark 的脚注在 `c.block(...)` 之后才读取可变字段 `count`，把这个读操作也提前可能改变结果，最小反例中读到的计数从 1 变成 0。[脚注源码，第 1008–1016 行](https://assets.mooncakes.io/assets/moonbit-community/cmark@0.4.17/cmark_html/html.mbt.html) |
| 用一个 `is` 表达字面量备选 | YAML 0.0.10 的 `Char::is_alpha` 连续对 `self` 做五次模式判断。一个 `self is ('0'..<='9' \| 'a'..<='z' \| 'A'..<='Z' \| '_' \| '-')` 就能写全原字符集。base64 0.16.15 的换行跳过逻辑，同样可以写成 `src[si] is (b'\x0a' \| b'\x0d')`。[YAML 源码，第 27–32 行](https://assets.mooncakes.io/assets/moonbit-community/yaml@0.0.10/char_utils.mbt.html) · [base64 源码，第 187、204 行](https://assets.mooncakes.io/assets/gmlewis/base64@0.16.15/base64-decode.mbt.html) · [core #4158](https://github.com/moonbitlang/core/pull/4158) | 首版可限于稳定的局部标量、内建比较、常量或区间，以及不引入绑定的模式。`next() == a \|\| next() == b` 可能读取两次。base64 的下标扩展要另外证明接收者是内建 `FixedArray[Byte]`，索引稳定且边界检查仍在。 |

用三条 YAML 查询扫描发布包中的全部 **1,116 个 `.mbt` 文件**，包括测试。下表只计可解析代码块中的 CST 形状，尚未逐处验证绑定和类型。带测试后缀指 `_test.mbt` 或 `_wbtest.mbt`，普通文件也可能内嵌测试。

| 结构查询 | 候选位置 | 涉及包数 | 其中位于带测试后缀的文件 |
| --- | ---: | ---: | ---: |
| 循环体首句把同一绑定解成二元组 | 183 | 6 | 49 |
| 对同一标识符连续用两个 `is`，或与两个常量比较 | 115 | 10 | 2 |
| `Iter::empty()`、`Iter::singleton(x)` 或直接对数组字面量调用 `.iter()` | 0 | 0 | 0 |

183 处里有 110 处来自 `CAIMEOX/symbit`，49 处来自 `Milky2018/moon_skrifa`。第二条只筛标识符，表中手工验证的 base64 下标写法超出了它的范围。两行候选也没有相加作为可修复总数。

扫描在 5 个包的 102 个文件中跳过了 320 个解析失败的代码块。其中 223 条诊断首先遇到 `try?`。迭代器候选为零尤其值得注意：`kesmeey/IndexMap@0.1.9` 的 `src/IndexMap_test.mbt:303、311、318` 实际上有三例，所在的测试块还含有旧式 `inspect!`。在合法源码中重放，三种查询形状都能命中。[IndexMap 发布源码](https://download.mooncakes.io/user/kesmeey/IndexMap/0.1.9.zip) · [三条调查查询](rules)

## 其他有明确使用场景的语法

| 语法 | 发布包中的机会 | 适用边界和对应的 core 改写 |
| --- | --- | --- |
| 数组里的条件展开 `..if` | 当天发布的 `mizchi/bit_diff@0.50.0` 在 `diff_ops.mbt:730–734` 先按条件压入 XDG 配置路径，再压入用户默认路径。可以在数组中直接写 `..if lookup() is Some(base) { [base + "/git/config"] }`，下一项写默认路径。[源码](https://assets.mooncakes.io/assets/mizchi/bit_diff@0.50.0/diff_ops.mbt.html) | 目录查询一次，路径构造留在对应分支，XDG 路径继续排第一。适合刚创建且尚未暴露给其他代码的短数组。[core #3992](https://github.com/moonbitlang/core/pull/3992) |
| 用推导式构造 Map | 同一包的 `diff_ops.mbt:288–291` 创建空表，再逐项写 `index_map[e.path] = e`。可以写成 `Map([for e in index_entries => (e.path, e)])`。[源码](https://assets.mooncakes.io/assets/mizchi/bit_diff@0.50.0/diff_ops.mbt.html) | 该处是字符串键和字段投影，重复键仍取最后的值。构造器接收键值对数组视图。推导式会先生成键值对，哈希和插入随后发生。自定义 Hash/Eq、依赖目标表的投影、显式容量和热路径均需单独判断。[core #3546](https://github.com/moonbitlang/core/pull/3546) |
| 向同一 builder 流式插值 `<+` | Rabbita 的 SSR 在 `ssr.mbt:180–182` 分三次写入结束标签。已验证可合为 `buf <+ "</\{tag}>"`。[源码](https://github.com/moonbit-community/rabbita/blob/4a20586a080bed3d557cbffd698cc26e3a496fd8/rabbita/internal/vdom/ssr.mbt#L180-L182) | 这里的 `tag` 已经是字符串。规则需要确认同一个 builder，并保留 HTML 转义、换行、写入顺序和可能抛错的插值边界。[core #4558](https://github.com/moonbitlang/core/pull/4558) |
| 倒序范围 `n>..0`，以及循环状态 `; acc = init` | cmark 的 `tokens_shorten_last_line` 从 `length()-1` 走到 0，仍要用下标回写元素。可改为 `for i in toks.0.length()>..0`。`fuzzy_match@0.2.6` 的 `fold_matching_indices_single_query` 可以把 `acc` 和 `query_idx` 显式放在循环头。[cmark 源码，第 144 行](https://assets.mooncakes.io/assets/moonbit-community/cmark@0.4.17/cmark/inline_struct.mbt.html) · [fuzzy_match 源码，第 36–53 行](https://assets.mooncakes.io/assets/moonbit-community/fuzzy_match@0.2.6/fuzzy_search.mbt.html) | 倒序依次访问 `n-1 … 0`，空输入访问零次。fuzzy_match 同文件第 20 行的另一个倒扫描只在字符匹配时减少 `query_idx`，不能把它当成每轮都减少的索引。已有 `cstyle_backward_*` 会提示部分 C 式循环，新增规则要覆盖它遗漏的更新形式。[core #3526](https://github.com/moonbitlang/core/pull/3526) · [core #3273](https://github.com/moonbitlang/core/pull/3273) |
| 字符串前缀模式和整串 `lexmatch` | `tiye/cirru-parser@0.3.0` 的 `Cirru::is_comment` 检查非空后访问第 0 项，嵌套模式 `self is Leaf([';', ..])` 能表达同一个谓词。cmark 的 `attribute_name_is_valid` 则有不同的首字符与后续字符规则，可用 `lexmatch` 的 `re"^[A-Za-z_:]([A-Za-z0-9_:.]\|-)*$"`。[Cirru 源码，第 145 行](https://assets.mooncakes.io/assets/tiye/cirru-parser@0.3.0/primes.mbt.html) · [cmark 源码，第 13 行](https://assets.mooncakes.io/assets/moonbit-community/cmark@0.4.17/cmark_html/attributes.mbt.html) | Cirru 分隔符是单个 ASCII 字符；任意 UTF-16 偏移和字符序号需要区别对待。cmark 处理的是完整 ASCII 属性名，两端锚点、首字符、空串都影响结果。对照测试枚举了含换行、非 ASCII 字符在内的 16,105 个短字符串。一般词法循环应由人复核。[core #4159](https://github.com/moonbitlang/core/pull/4159) · [core #4864](https://github.com/moonbitlang/core/pull/4864) · [core #4865](https://github.com/moonbitlang/core/pull/4865) |
| 用字节模式写定长布局 | `mizchi/cbor@0.1.1` 的 `decode_double` 手工把 8 个字节移位合成大端位串。保留 `length() >= 9` 的原检查后，可以匹配 `[b'\xfb', u64be(bits), ..]`，再调用 `bits.reinterpret_as_double()`。[源码，第 213–229 行](https://assets.mooncakes.io/assets/mizchi/cbor@0.1.1/cbor.mbt.html) | 短且标签错误的输入必须先报「长度不足」，尾部多余字节继续允许。取发布版原函数做差分，对照了 256 个首字节 × 12 种长度，再加负零和带载荷的 NaN；比较原始位串和错误消息。[core #4846](https://github.com/moonbitlang/core/pull/4846) |
| 在 or-pattern 中用 `with` 提供分支值 | `Yoorkin/ArgParser@0.2.1` 的 `Set(r)` 和 `Clear(r)` 都写入引用并携带同一个剩余参数序列 `continue`，区别是写入的布尔值。两个模式可以分别用 `with value = true` 和 `with value = false`，共享一次写入和跳转。[源码，第 50–57 行](https://assets.mooncakes.io/assets/Yoorkin/ArgParser@0.2.1/arg.mbt.html) | 使用带括号的 alternative，核对引用、跳转目标、移动的表达式和模式优先级。公共分支很短时，保留原写法也容易读。这一项用缩小的双分支例子验证。[core #3808](https://github.com/moonbitlang/core/pull/3808) |
| 用 `if … is` 或 `guard … is` 表达单个有效分支 | `tiye/respo@0.3.4` 收集虚拟 DOM 监听器时，`Some(listener)` 执行一次 push，`None` 为空。这里适合 `if … is Some(listener)`；第 33 行对子树的递归必须在两种情况下都执行。[源码，第 28–33 行](https://assets.mooncakes.io/assets/tiye/respo@0.3.4/global_event.mbt.html) | core 的尾部匹配可以用 `guard` 去掉嵌套。把同一个 guard 搬到 Respo 的整个分支会跳过本应执行的递归。现有 `match_option` / `match_option_early_exit` 已覆盖其中一些形状。[core #3946](https://github.com/moonbitlang/core/pull/3946) |
| 迭代器字面量 `[\|…\|]` | IndexMap 的测试可以把 `[(1, 1)].iter()` 写成 `[\|(1, 1)\|]`，把 `Iter::empty()` 写成 `[\|\|]`。先修好所在块的旧式调用标记才适合做结构搜索。[发布源码](https://download.mooncakes.io/user/kesmeey/IndexMap/0.1.9.zip) | 普通字面量元素在构造时求值，仍然只遍历一次。测试核对元素调用时机、`size_hint` 和剩余元素。带回调的 `Iter(...)` 以及对既有数组或切片调用 `.iter()` 各有自己的行为。[core #4080](https://github.com/moonbitlang/core/pull/4080) |

## 会影响升级的旧语法

有些旧写法在类型检查前就会被拒绝。对这些代码，可以从词法 token 和解析诊断定位迁移点，再用当前编译器验证新文本。

- `CAIMEOX/symbit@0.5.10` 的 `expr_rational` 把 `try? f()` 立刻交给 `Ok(value)` / `Err(_)` 匹配。这里可直接用 `try f() catch { _ => fallback() }`。Respo 的 CSS 代码会把结果当作数据继续匹配，保留 `Result` 时可写 `try Ok(f()) catch { e => Err(e) }`。nightly 对旧式 `try?` 报 E3002；两种新用法都经过编译。[symbit 源码，第 37 行](https://assets.mooncakes.io/assets/CAIMEOX/symbit@0.5.10/symalgebras/quaternion.mbt.html) · [Respo 源码，第 25 行](https://assets.mooncakes.io/assets/tiye/respo@0.3.4/node/css.mbt.html) · [core #4377](https://github.com/moonbitlang/core/pull/4377)
- `kesmeey/IndexMap@0.1.9` 的 `src/IndexMap.mbt:31` 仍用 `fn new[K, V](...)`，测试还用 `inspect!(...)`。最小编译对照中 `fn f[T]` 和后缀调用 `f!()` 都得到 E3002，改为 `fn[T] f` 和 `f()` 后通过。查找后缀调用需要区分 `guard!`、注释和字符串。[发布源码](https://download.mooncakes.io/user/kesmeey/IndexMap/0.1.9.zip)
- Rabbita 的 `url/url.mbt:8` 仍在类型声明之后写 `derive(Debug, Eq, Compare)`。本轮运行原包测试时，编译器为这种写法给出了把 `#derive(...)` 放到类型之前的弃用提示。可以直接复用编译器诊断。[Rabbita 源码](https://assets.mooncakes.io/assets/moonbit-community/rabbita@0.17.0/url/url.mbt.html)

## 验证和复跑

下表是对完整发布包的临时副本运行 `moon test` 的结果。基线先运行一次，只改所列位置后再运行一次。发布包自带测试的数量和覆盖范围各不相同，尤其是 bit_diff 只有 1 项。本文没有据此推算速度或内存收益。

| 发布包 | 本轮实改位置 | 目标 | 原版通过 | 改写后通过 |
| --- | --- | --- | ---: | ---: |
| moonbit-community/cmark 0.4.17 | HTML 属性名整串匹配、倒序更新最后一个 token | wasm | 435 | 435 |
| Milky2018/moon_skrifa 0.2.0 | `autohint.mbt:203`、`autohint_metrics.mbt:524、720` 三处循环头解构 | wasm | 256 | 256 |
| moonbit-community/yaml 0.0.10 | `Char::is_alpha` 的备选模式 | wasm | 84 | 84 |
| moonbit-community/rabbita 0.17.0 | 订阅表循环头解构、SSR 结束标签插值 | wasm | 71 | 71 |
| gmlewis/base64 0.16.15 | 两处跳过 CR/LF 的字节判断 | wasm | 29 | 29 |
| moonbit-community/fuzzy_match 0.2.6 | 匹配位置与累加器的循环状态 | wasm | 12 | 12 |
| mizchi/bit_diff 0.50.0 | 路径索引的 Map 推导式、候选配置路径的条件展开 | native | 1 | 1 |
| **合计** | | | **888** | **888** |

CBOR 采用原函数的独立差分测试，ArgParser、Cirru、Respo、IndexMap 的相应语法用最小程序验证。本目录另有 12 项可运行的行为测试，包括重复键顺序、求值时机和可变字段读取。[模式与输入边界](patterns_wbtest.mbt) · [求值与遍历](evaluation_wbtest.mbt)

从 MoonGrep 仓库根目录运行。第二条命令直接在终端显示源码和位置，把路径换成要调查的目录即可。

```sh
MOON_WORK=off moon -C examples/syntax-adoption test --target wasm,native
moon run --target native . -- scan PATH_TO_SOURCE --rules examples/syntax-adoption/rules
```

要重建相同语料和计数，可执行以下 Bash 命令。下载的文件和扫描结果写入临时目录。

```bash
(
  set -eu
  sample=$(mktemp -d)
  tail -n +2 examples/syntax-adoption/corpus.tsv |
    while IFS="$(printf '\t')" read -r module version digest; do
      archive="$sample/release.zip"
      curl -fsSL "https://download.mooncakes.io/user/$module/$version.zip" -o "$archive"
      printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c -
      mkdir -p "$sample/src/$module"
      unzip -q "$archive" -d "$sample/src/$module"
    done
  moon run --target native . -- scan "$sample/src" --rules examples/syntax-adoption/rules --json \
    > "$sample/findings.jsonl" 2> "$sample/diagnostics.log"
  jq -s 'group_by(.rule_id) | map({rule: .[0].rule_id, count: length})' "$sample/findings.jsonl"
  printf '%s\n' "$sample"
)
```
