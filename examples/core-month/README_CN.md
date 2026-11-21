# 数值、遍历与文本规则

[English](README.md)

`moongrep lint` 默认加载以下规则，内建规则 ID 的前缀为 `moonbitlang/`。

| 规则 | 匹配的写法 | 建议写法 |
| --- | --- | --- |
| [float_finiteness](../../internal/rule/lintrules/moonbitlang/float_finiteness.yaml) | `x.is_nan() \|\| x.is_inf()` 或 `!x.is_nan() && !x.is_inf()` | 分别写成 `!x.is_finite()` 或 `x.is_finite()` |
| [integer_min](../../internal/rule/lintrules/moonbitlang/integer_min.yaml) | `if x < best { best = x }` | `best = best.min(x)` |
| [integer_max](../../internal/rule/lintrules/moonbitlang/integer_max.yaml) | `if i - k > 1 { i - k } else { 1 }` | `(i - k).max(1)` |
| [iter_next_loop](../../internal/rule/lintrules/moonbitlang/iter_next_loop.yaml) | `while it.next() is Some(x)` | `for x in it`，保留循环体、`break` 和 `nobreak` |
| [direct_view_iteration](../../internal/rule/lintrules/moonbitlang/direct_view_iteration.yaml) | `for ch in text.iter()` | `for ch in text` |
| [slice_to_end](../../internal/rule/lintrules/moonbitlang/slice_to_end.yaml) | `s[i:s.length()]` 或 `s[:s.length()]` | `s[i:]` 或 `s[:]` |
| [builder_stream_interpolation](../../internal/rule/lintrules/moonbitlang/builder_stream_interpolation.yaml) | `buf.write_string("key=\{i}")` | `buf <+ "key=\{i}"` |

数值规则会确认当前标准库公开了建议使用的方法。浮点判断必须读取同一个不可变的 `Float` 或 `Double` 绑定，两个谓词的顺序可以互换。如果后面还有其他条件，只标记这两个谓词。用展开式验证 `is_finite()` 的断言会保留。两条整数规则都支持直接返回值的 `if` 和对可变局部变量的条件赋值。重复出现的操作数可以是整数常量、局部绑定或简单的内建整数加减表达式。

遍历规则要求每次从同一个不可重新赋值的 `Iter` 绑定取值，`Some` 的内部模式可以是变量或 `_`。直接遍历和省略切片终点适用于 `String`、`StringView`、`Bytes` 和 `BytesView`。切片和 `length()` 必须作用于同一个值，也支持 `self.text` 这样的一层字段。起点必须是简单、稳定的值。

流式插值要求调用 `StringBuilder` 对 `Logger::write_string` 的标准实现。每个插值项必须是内建标量的字面量或不可变局部绑定。像 `buf.to_string()` 这样的插值表达式可能读到刚刚写入的前缀。

## 可选审查规则

用 `scan --rules` 运行以下结构查询，每个命中位置都需要核对改写条件。

| 规则 | 可考虑的改写 | 需要核对的条件 |
| --- | --- | --- |
| [review_fixed_array_overwrite](review/fixed_array_overwrite.yaml) | 将 `FixedArray::make(n, seed)` 和后续的完整填充循环改成 `FixedArray::makei`。 | 即使 `n == 0`，求值 `seed` 也可能产生副作用。填充边界必须一致，循环中也不能读取或暴露尚未填好的数组。 |
| [review_iter_then_predicate](review/iter_then_predicate.yaml) | 将 `xs.iter().any(p)` 或 `xs.iter().all(p)` 改成集合上的 `any` 或 `all`。 | 核对集合的遍历行为。构造谓词时若向数组追加元素，两种写法可能访问不同的元素。 |
| [review_find_then_split](review/find_then_split.yaml) | 将 `find` 后围绕分隔符取左右切片改成 `split_once`。 | 确认索引没有其他用途，且右侧切片恰好跳过整个分隔符。查询只匹配单个 `=`、`;`、`/`、`:` 或 `,`。 |

## 运行

在 MoonGrep 仓库根目录执行以下命令，可以分别查看数值示例、单条切片规则和可选审查规则。默认输出包含源码和位置。

```sh
moon run --target native . -- lint examples/core-month/numbers.mbt --target wasm
moon run --target native . -- scan examples/core-month/text.mbt --rule internal/rule/lintrules/moonbitlang/slice_to_end.yaml --target wasm
moon run --target native . -- scan examples/core-month/review_examples.mbt --rules examples/core-month/review
```
