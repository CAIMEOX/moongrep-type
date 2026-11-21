# 标准库写法

[English](README.md)

以下命令在 MoonGrep 仓库根目录运行。外层的 `--target native` 用来运行 MoonGrep，传给 `lint` 或 `scan` 的 `--target wasm` 指定示例的检查后端。

```sh
moon run --target native . -- lint examples/stdlib-patterns/idioms.mbt --target wasm
moon run --target native . -- scan examples/stdlib-patterns/idioms.mbt --rule internal/rule/lintrules/moonbitlang/map_get_contains.yaml --target wasm
```

下表中的每一行都对应一份[内建 YAML](../../internal/rule/lintrules/moonbitlang)。内建 ID 由 `moonbitlang/` 加上规则名组成。自定义形状匹配后，仍须通过对应的语义检查。

## 集合与文本查询

| 规则 | 匹配的写法 | 建议与条件 |
| --- | --- | --- |
| `collection_is_empty` | `xs.length() == 0`、`!= 0`、`> 0` 以及交换两端的等价比较 | 使用 `xs.is_empty()` 或其否定。支持标准数组、只读数组、数组视图、Map、文本和字节序列及其视图。 |
| `string_find_contains` | `s.find(needle) is Some(_)` | 使用 `s.contains(needle)`，也适用于空搜索串。 |
| `string_prefix_presence` | `s.strip_prefix(prefix) is Some(_)` | `s.has_prefix(prefix)` |
| `string_suffix_presence` | `s.strip_suffix(suffix) is Some(_)` | `s.has_suffix(suffix)` |
| `map_get_contains` | `m.get(k) is Some(_)` | `m.contains(k)`。即使键对应的值为 `None`，该键也存在。 |
| `array_search_contains` | `a.search(v) is Some(_)` | 元素为使用内建相等比较的基本类型时，可用 `a.contains(v)`。 |
| `array_search_by_any` | `a.search_by(p) is Some(_)` | `a.any(p)`。谓词必须同步，短路顺序保持一致。 |
| `iter_drop_next` | `it.drop(3).next()` | `it.nth(3)`。参数限于可表示为 Int 的非负十进制整数字面量。 |
| `map_get_default` | `m.get(k).unwrap_or(d)` | 默认值为基本类型字面量或不可变局部绑定时，可用 `m.get_or_default(k, d)`。带副作用的默认值如果移到查表之前求值，可能改变结果。 |

判断是否存在时，也支持 `is None` 和旧方法 `is_some()`、`is_none()`。匹配 `None` 时将建议的谓词取反。如果模式还检查或绑定了载荷，就需要保留该匹配。方法和构造函数都必须解析到标准库。

判空建议只改写条件。例如用 `!queue.is_empty()` 控制清空队列的循环时，循环体中追加的元素依然会被处理。`map_get_default` 只读表，若在键缺失时写入默认值，后续查找就会得到不同的结果。

## 手写的 Option 和 Result 操作

这些规则的示例在 [matches.mbt](matches.mbt)。两个分支的顺序可以交换。被转发的值必须是对应模式绑定的变量。

| 规则 | 匹配分支 | 建议写法 |
| --- | --- | --- |
| `match_option_map` | `Some(x) => Some(f(x))`、`None => None` | `v.map(x => f(x))` |
| `match_option_bind` | `Some(x) => f(x)`、`None => None` | `v.bind(x => f(x))` |
| `match_option_unwrap_or` | `Some(x) => x`、`None => d` | `v.unwrap_or(d)` |
| `match_option_unwrap_or_else` | `Some(x) => x`、`None => read()` | `v.unwrap_or_else(() => read())` |
| `match_result_map` | `Ok(x) => Ok(f(x))`、`Err(e) => Err(e)` | `r.map(x => f(x))` |
| `match_result_map_err` | `Ok(x) => Ok(x)`、`Err(e) => Err(f(e))` | `r.map_err(e => f(e))` |
| `match_result_bind` | `Ok(x) => f(x)`、`Err(e) => Err(e)` | `r.bind(x => f(x))` |
| `match_result_to_option` | `Ok(x) => Some(x)`、`Err(_) => None` | `r.to_option()` |
| `match_result_unwrap_or` | `Ok(x) => x`、`Err(_) => d` | `r.unwrap_or(d)` |
| `match_result_unwrap_or_else` | `Ok(x) => x`、`Err(_) => read()` | `r.unwrap_or_else(() => read())` |

变换可以是同步的一元函数调用（允许受检错误），也可以是使用基本类型字面量的算术或比较，例如 `Some(x + 1)`。`bind` 的回调须返回所需的 Option 或 Result 类型。立即求值的默认值必须是基本类型字面量或不可变局部绑定。无参回退调用留在闭包中，可以抛出错误。带 guard、复杂载荷模式或额外语句的分支需要单独判断。

## 短路循环与 ASCII 谓词

这些规则的示例在 [predicates.mbt](predicates.mbt)。

| 规则 | 匹配的写法 | 建议写法 |
| --- | --- | --- |
| `loop_any` | 命中时以 `true` 跳出，遍历结束取 `false` | `xs.any(x => p(x))` |
| `loop_all` | 测试失败时以 `false` 跳出，遍历结束取 `true` | `xs.all(x => p(x))` |
| `loop_find_first` | 命中时以 `Some(x)` 跳出，遍历结束取 `None` | `it.find_first(x => p(x))` |
| `char_ascii_digit` | `'0' <= c && c <= '9'` | `c.is_ascii_digit()` |
| `char_ascii_lowercase` | `c is ('a'..<='z')` | `c.is_ascii_lowercase()` |
| `char_ascii_uppercase` | `'Z' >= c && c >= 'A'` | `c.is_ascii_uppercase()` |

循环需要有一个条件出口和对应的 `nobreak`。谓词可以调用同步函数，或将元素与基本类型字面量比较。`all` 也接受 `guard`。标准数组类型和 `Iter` 支持 `any`、`all`，返回命中元素的 `find_first` 规则要求 `Iter`。找到元素后，调用者仍可从迭代器取出后续元素。

引入闭包的匹配和循环规则会核对每个具名回调的绑定。被 `#locals` 标记的参数必须留在其声明函数内，其他同名绑定仍可匹配。

三条 ASCII 规则要求在同一个稳定的 `Char` 绑定上做包含两端的范围比较，两个条件可以交换，也可以使用一个闭区间模式。边界值须完全相同。UTF-16 码元的接收者类型不同。

[边界示例](counterexamples.mbt)包含会增长的队列和受 `#locals` 限制的回调。如果 `map` 或 `bind` 返回原载荷，参见 [Option 与 Result 恒等规则](../semantic-theorems/README_CN.md#适用条件)。
