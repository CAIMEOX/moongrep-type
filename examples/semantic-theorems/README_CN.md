# 集合、Option 与 Result 规则

[English](README.md)

## 规则列表

每行给出 YAML 的 `semantic.check` 名称。对应的内建规则 ID 以 `moonbitlang/` 开头，并把连字符换成下划线，例如 `moonbitlang/array_filter_count`。

| 检查项 | 匹配的表达式 → 建议写法 |
| --- | --- |
| `array-filter-count` | `a.filter(p).length()` → `a.count_if(p)` |
| `iter-filter-count` | `it.filter(p).count()` → `it.count_if(p)` |
| `iter-filter-next` | `it.filter(p).next()` → `it.find_first(p)` |
| `iter-find-first-exists` | `it.find_first(p) is Some(_)` → `it.any(p)`，`is None` → `!it.any(p)`。也支持 `.is_some()` 和 `.is_none()`。 |
| `iter-map-flatten` | `it.map(f).flatten()` → `it.flat_map(f)` |
| `option-map-fusion` | `o.map(f).map(g)` → `o.map(x => g(f(x)))` |
| `result-map-fusion` | `r.map(f).map(g)` → `r.map(x => g(f(x)))` |
| `result-map-err-fusion` | `r.map_err(f).map_err(g)` → `r.map_err(e => g(f(e)))` |
| `option-bind-map` | `o.bind(x => Some(body))` → `o.map(x => body)` |
| `result-bind-map` | `r.bind(x => Ok(body))` → `r.map(x => body)` |
| `result-map-flatten` | `r.map(f).flatten()` → `r.bind(f)` |
| `option-filter-fusion` | `o.filter(p).filter(q)` → `o.filter(x => p(x) && q(x))` |
| `option-map-default` | `o.map(f).unwrap_or_else(d)` → `o.map_or_else(d, f)` |
| `option-map-identity` | `o.map(x => x)` → `o` |
| `result-map-identity` | `r.map(x => x)` → `r` |
| `option-bind-identity` | `o.bind(x => Some(x))` → `o` |
| `result-bind-identity` | `r.bind(x => Ok(x))` → `r` |
| `option-unwrap-some` | `Some(x).unwrap()` → `x` |
| `result-unwrap-ok` | `Ok(x).unwrap()` → `x` |
| `result-unwrap-err` | `Err(e).unwrap_err()` → `e` |

## 适用条件

**迭代器消费。** 计数会遍历完整输入。查找在第一次命中后停止，后续元素可继续使用。判断是否找到元素时，模式必须是标准的 `None` 或 `Some(_)`，也可以写成 `Option::Some(_)`。绑定载荷或匹配嵌套模式还有额外用途。`flat_map` 保留内层迭代器的惰性遍历。这些集合规则保留接收者和回调表达式的求值顺序，也适用于通过工厂创建的回调。

**回调求值。** 合并 Option 或 Result 的 `map` 时，只有相应分支会依次调用 `f` 和 `g`。合并 Option 的两个 `filter` 时，只有 `p` 成功才会执行 `q`。合并惰性默认值时只执行被选中的变换或回退函数。被移入闭包的回调必须是不可变函数绑定，或没有捕获可变绑定的 lambda。组合回调时，各函数的 `return` 仍应留在各自的作用域。回调必须同步，两种方法都支持的受检错误会按原路径传播。

**构造函数与恒等变换。** 将 `bind` 改为 `map` 时，只去掉 lambda 返回值最外层的标准 `Some` 或 `Ok`。直接从该回调提前返回可能改变结果。在 `r.map(f).flatten()` 中，接收者与 `f` 返回的 `Result` 必须具有相同的错误类型。恒等规则要求返回的变量确实是回调参数。重新构造的变体可能具有不同的对象身份，因此四条 map/bind 恒等规则仅在紧接着检查标签、匹配但不绑定整个变体，或调用标准载荷取值方法时生效。直接解包已知的标准构造函数会保留载荷，且只求值一次。

## 运行

在仓库根目录可以对示例运行内建规则，也可以只选择一份 YAML。示例涵盖[集合](collections.mbt)、[回调合并](option_fusion.mbt)和[恒等变换](identities.mbt)。

```sh
moon run --target native . -- lint examples/semantic-theorems/option_fusion.mbt --target wasm
moon run --target native . -- scan examples/semantic-theorems/collections.mbt --rule internal/rule/lintrules/moonbitlang/iter_filter_count.yaml --target wasm
```

自定义 YAML 可以收紧候选的形状或增加 guard。选定的语义检查仍会核对标准库符号、类型和绑定身份。[规则规范](../../internal/docs/RuleSpec_CN.md#语义规则)
