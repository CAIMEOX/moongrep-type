# 从 core 一个月的改动提炼 MoonGrep 规则

这组规则来自北京时间 2026-10-21 00:00 到 2026-11-21 00:00 的 core 主线。取两个时刻之前的最后一次提交，分别是 `47383531` 和 `f157f574`。中间有 519 次一阶父提交，1,093 个 MoonBit 源文件发生变化。其中仅 `async/` 就新增了 343 个源文件，所以除了比较两端的命中数，还要回到同一个函数检查改写前后。[完整 diff](https://github.com/moonbitlang/core/compare/4738353132cfe6a84651377b5523b66f5f6c6742...f157f574d3afc3c50df96b15682d2e0eb671d08a)

## 运行

在 MoonGrep 仓库根目录使用十一月 nightly 运行。外层 `--target native` 用来运行 MoonGrep，传给 `lint` 或 `scan` 的 `--target wasm` 选择待分析代码的后端。默认输出会显示文件、行列、命中的源码和建议。前两条命令调用语义检查，第三条只做结构搜索。

```sh
moon run --target native . -- lint examples/core-month/numbers.mbt --target wasm
moon run --target native . -- scan examples/core-month/text.mbt --rule internal/rule/lintrules/moonbitlang/slice_to_end.yaml --target wasm
moon run --target native . -- scan examples/core-month/review_examples.mbt --rules examples/core-month/review
MOON_WORK=off moon -C examples/core-month test --target wasm,native
```

## 七条内建规则

每条规则先用 YAML 形状筛选，再用 `moon ide` 核实所需的类型、符号或绑定。下面的 ID 在 `lint` 输出里带有 `moonbitlang/` 前缀。

| 规则 | core 里的改写 | 提示成立的条件 |
| --- | --- | --- |
| [float_finiteness](../../internal/rule/lintrules/moonbitlang/float_finiteness.yaml) | `x.is_inf() \|\| x.is_nan()` → `!x.is_finite()`，两个否定条件合取时用 `x.is_finite()` | 两次读取同一不可变局部值，均为标准库 Float 或 Double 谓词，公开接口提供 `is_finite`。保留后续的 `x == 0.0` 和直接验证该 API 的独立断言。[math 实际改动](https://github.com/moonbitlang/core/commit/a29b3d7805e8be9181d8bb96ac5a2392e8b1f1b1) |
| [iter_next_loop](../../internal/rule/lintrules/moonbitlang/iter_next_loop.yaml) | `while it.next() is Some(x)` → `for x in it` | 同一个不可重新赋值的迭代器，标准库 `Iter::next` 和 `Option::Some`，内部模式是变量或 `_`。提示只标循环头，保留 `break` 与 `nobreak`。[hashset 改动](https://github.com/moonbitlang/core/pull/4479) |
| [direct_view_iteration](../../internal/rule/lintrules/moonbitlang/direct_view_iteration.yaml) | `for ch in token.iter()` → `for ch in token` | 单元素遍历，接收者为 String、StringView、Bytes 或 BytesView，调用对应的标准库 `iter`。[JSON Pointer 改动](https://github.com/moonbitlang/core/commit/0d5743688bc2f6aaef65c2b787902d0dafcc8495) |
| [slice_to_end](../../internal/rule/lintrules/moonbitlang/slice_to_end.yaml) | `self.input[end:self.input.length()]` → `self.input[end:]` | 文本或字节的同一个值，也支持同一局部对象上的一层同名字段。起点限于可确认稳定的值，防止第一次读字段之后它又被替换。[正则切片改动](https://github.com/moonbitlang/core/pull/4469) |
| [builder_stream_interpolation](../../internal/rule/lintrules/moonbitlang/builder_stream_interpolation.yaml) | `buf.write_string("key=\{i}")` → `buf <+ "key=\{i}"` | 接收者确为 StringBuilder，并解析到其标准 Logger 实现。模板至少有一个插值，插值限于内建标量常量或不可变局部值。[JSON 基准的新版源码](https://github.com/moonbitlang/core/blob/f157f574d3afc3c50df96b15682d2e0eb671d08a/json/lex_string_bench_test.mbt#L49) |
| [integer_min](../../internal/rule/lintrules/moonbitlang/integer_min.yaml) | `if del < best { best = del }` → `best = best.min(del)` | 支持直接选值和对可变局部变量的普通赋值。重复项限于局部值、整数常量或简单标准整数加减；检查比较符号与该整数类型公开的 `min` 方法。[编辑距离改动](https://github.com/moonbitlang/core/pull/4445) |
| [integer_max](../../internal/rule/lintrules/moonbitlang/integer_max.yaml) | `if i - k > 1 { i - k } else { 1 }` → `(i - k).max(1)` | 与 `integer_min` 对称，同样核对实际 SDK 的方法；浮点数、用户比较函数和重复调用不在范围内。[改写后的边界计算](https://github.com/moonbitlang/core/blob/f157f574d3afc3c50df96b15682d2e0eb671d08a/internal/edit_distance/edit_distance.mbt#L149) |

## 在两个完整快照上复查

对原样导出的两个快照各自执行 `moon check --target wasm`。十月使用官方 `0.10.16+b1a0e846e`，十一月使用 `0.10.22+c5d6f7c27-nightly`。用同一个 MoonGrep 可执行文件扫描所有受版本控制的 `.mbt`，包括测试。左边两列只运行 YAML 的结构模式；右边两列运行正式规则，包含语义过滤。一次结构命中可能需要多次 IDE 查询。

| 规则 | 十月结构命中 | 十一月结构命中 | 十月语义命中 | 十一月语义命中 |
| --- | ---: | ---: | ---: | ---: |
| float_finiteness | 23 | 10 | 0 | 8 |
| iter_next_loop | 34 | 22 | 24 | 12 |
| direct_view_iteration | 2 | 7 | 1 | 0 |
| slice_to_end | 7 | 6 | 2 | 1 |
| builder_stream_interpolation | 318 | 155 | 2 | 0 |
| integer_min | 85 | 88 | 25 | 25 |
| integer_max | 47 | 57 | 21 | 24 |
| **合计** | **516** | **345** | **75** | **70** |

- **有限数判断**。十月 SDK 尚未提供 `is_finite`，所以正式规则在十月快照上没有给出建议。为分开观察源码和 SDK 的变化，在十一月快照里原样放回十月的六份 math 文件，重新通过类型检查，用同一套十一月工具链扫描这些文件，得到 **8 → 0**。六份文件是 `algebraic_double_nonjs.mbt`、`hyperbolic_double_nonjs.mbt`、`log_double_nonjs.mbt`、`trig_double_nonjs.mbt`、`trig_double_sincos_non_native_or_js.mbt` 和 `utils.mbt`。十一月全库另外命中的 8 处都在测试文件中，分布在 math（5）、json（1）、simd（1）和 internal/strconv（1）。[新增 API](https://github.com/moonbitlang/core/commit/03b005b8b988e532627afc397379a79a3e652ab6) · [旧源码](https://github.com/moonbitlang/core/blob/4738353132cfe6a84651377b5523b66f5f6c6742/math/algebraic_double_nonjs.mbt#L46) · [新源码](https://github.com/moonbitlang/core/blob/f157f574d3afc3c50df96b15682d2e0eb671d08a/math/algebraic_double_nonjs.mbt#L46)
- **整数极值**。单看整个仓库，`integer_min` 的总数相同。但在 `internal/edit_distance/edit_distance.mbt`，六处 min 和一处 max 全部消失。新版把两次更新最小值写成了 `sub.min(del).min(ins)`。[旧源码](https://github.com/moonbitlang/core/blob/4738353132cfe6a84651377b5523b66f5f6c6742/internal/edit_distance/edit_distance.mbt#L104) · [新源码](https://github.com/moonbitlang/core/blob/f157f574d3afc3c50df96b15682d2e0eb671d08a/internal/edit_distance/edit_distance.mbt#L103)
- **流式插值**。当月有 28 条提交标题包含 `streaming string interpolation`。十月的 318 个结构候选包含普通 `write_string` 调用。语义检查最终只留下两处，分别在 JSON 基准与正则解析器测试中，两处在十一月都已改写。限制插值表达式很重要。例如目标缓冲区已有 `"A"` 时，插值中读取 `buf.to_string()`，整串写入得到 `"AprefixA"`，流式写入会得到 `"AprefixAprefix"`。[JSON 改动](https://github.com/moonbitlang/core/commit/8cb2d4c5e9fb60d0e7d3b33628e2cc9d36a4a0e2) · [正则解析器改动](https://github.com/moonbitlang/core/commit/0046a07c82b780df5aa6d64a2dcdc46d10f3af71) · [行为测试](month_wbtest.mbt)

两次正式全库扫描分别执行了 620 和 551 次语义查询，诊断数均为零。报告中的命中是建议的位置；文件与 API 都在变化，不能用两列之差估算当月修复量。

## 三条手动审查查询

| YAML | 何时考虑改写 | 为什么需要审查 |
| --- | --- | --- |
| [fixed_array_overwrite](review/fixed_array_overwrite.yaml) | `FixedArray::make(n, seed)` 后以相同边界逐项填满，考虑 `makei`。两端 **1 → 0**。 | 改写可能删掉 `seed` 的求值，哪怕长度为零。还需检查填充时是否读取正在构造的数组。[core diff](https://github.com/moonbitlang/core/commit/8452487f5dbfa695dfc381b64c67b75b1b8ad357) |
| [iter_then_predicate](review/iter_then_predicate.yaml) | `xs.iter().all(p)` 或 `any(p)`，检查集合是否有合适的直接方法。两端 **18 → 17**。 | 如果构造 `p` 会往数组追加元素，原写法可只访问 `[1]`，直接调用可访问 `[1, 2]`。[core diff](https://github.com/moonbitlang/core/commit/04b22a699ed2c9ebeda56dd0e2a59c8168b2daaa) · [可运行反例](review_wbtest.mbt) |
| [find_then_split](review/find_then_split.yaml) | 找到单个标点再做左右切片，考虑 `split_once`。完整两端 **0 → 0**，对月中 cookie 重构的父提交与该提交单独跑是 **1 → 0**。 | 核实分隔符宽度、左右空串和后续索引用途。以 `"::"` 分隔却只跳过一位会剩下一个冒号，`split_at` 的右半边还包含分隔符。[cookie 改动](https://github.com/moonbitlang/core/commit/477139ad087d4414928faa2f5fa8718818ffe68e) |

还有一种看起来适合普推的改动是 `lo..<(hi + 1)` 改成 `lo..<=hi`。当 `lo` 和 `hi` 都取 `@int.MAX_VALUE` 时，前者的上界溢出，循环为空；后者遍历一个元素。这个例子只收进行为测试。[边界测试](review_wbtest.mbt)

## 复现快照扫描

从仓库根目录运行，令 `CORE_GIT` 指向包含两个提交的 core 仓库，`OCT_SDK` 和 `NOV_SDK` 分别指向上述 SDK 根目录。所有历史文件都导出到临时目录。

```sh
MOON_WORK=off moon build --target native .
mg="$PWD/_build/native/debug/build/moongrep.exe"
work=$(mktemp -d)
mkdir -p "$work/rules" "$work/oct" "$work/nov"
for rule in float_finiteness iter_next_loop direct_view_iteration slice_to_end builder_stream_interpolation integer_min integer_max; do
  cp "internal/rule/lintrules/moonbitlang/$rule.yaml" "$work/rules/"
done
git -C "$CORE_GIT" archive 4738353132cfe6a84651377b5523b66f5f6c6742 | tar -x -C "$work/oct"
git -C "$CORE_GIT" archive f157f574d3afc3c50df96b15682d2e0eb671d08a | tar -x -C "$work/nov"
for month in oct nov; do
  sdk=$OCT_SDK
  if [ "$month" = nov ]; then sdk=$NOV_SDK; fi
  (
    export MOON_HOME="$sdk" PATH="$sdk/bin:$PATH" MOON_WORK=off NO_COLOR=1
    moon -C "$work/$month" check --target wasm --no-mbti &&
      "$mg" scan "$work/$month" --rules "$work/rules" --target wasm --verbose
  )
done
```

要复现表中的结构命中数，把这七份 YAML 的 `semantic.patterns` 原样提升为顶层 `patterns`，并移除 `semantic` 字段，然后用 `scan --rules` 分别扫描两个目录。要复现三条审查查询，把规则目录换成 `examples/core-month/review` 即可。
