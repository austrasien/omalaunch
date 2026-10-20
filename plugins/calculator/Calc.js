// Arithmetic for the calculator plugin. A small recursive-descent parser:
//
//   expr   := term (("+" | "-") term)*
//   term   := unary (("*" | "/" | "×" | "÷" | "mod") unary | implicit unary)*
//   unary  := ("-" | "+") unary | power        (so -2^2 = -4)
//   power  := postfix ("^" unary)?
//   postfix:= atom ("%" | "!")*
//   atom   := number | constant | function "(" args ")" | "(" expr ")"
//
// A comma between digits is a decimal separator (3,5 = 3.5); arguments are
// separated by ";" or ", ".

var FUNCTIONS = {
  sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
  ln: Math.log, log: Math.log10, log2: Math.log2, exp: Math.exp,
  sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
  min: Math.min, max: Math.max, pow: Math.pow
}
var CONSTANTS = { pi: Math.PI, "π": Math.PI, e: Math.E, tau: 2 * Math.PI }

function tokenize(src) {
  var s = String(src).replace(/(\d),(\d)/g, "$1.$2").replace(/\s+/g, " ").trim()
  var tokens = []
  var i = 0
  while (i < s.length) {
    var c = s.charAt(i)
    if (c === " ") { i++; continue }
    var num = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(s.slice(i))
    if (num) {
      var raw = num[0].replace(/\s/g, "")
      tokens.push({ t: "num", v: parseFloat(raw) })
      i += num[0].length
      continue
    }
    var word = /^(π|[a-z]+)/i.exec(s.slice(i))
    if (word) {
      var w = word[0].toLowerCase()
      // "3x4" means 3 × 4.
      if (w === "x" && tokens.length && (tokens[tokens.length - 1].t === "num" || tokens[tokens.length - 1].t === ")")) {
        tokens.push({ t: "op", v: "*" })
      } else if (w === "mod") {
        tokens.push({ t: "op", v: "mod" })
      } else {
        tokens.push({ t: "word", v: w })
      }
      i += word[0].length
      continue
    }
    if ("+-*/^%!();×÷,".indexOf(c) >= 0) {
      if (c === "×") c = "*"
      if (c === "÷") c = "/"
      if (c === "(" || c === ")") tokens.push({ t: c })
      else if (c === ";" || c === ",") tokens.push({ t: "sep" })
      else tokens.push({ t: "op", v: c })
      i++
      continue
    }
    throw new Error("unexpected " + c)
  }
  return tokens
}

function factorial(n) {
  if (n < 0 || n !== Math.floor(n) || n > 170) throw new Error("bad factorial")
  var r = 1
  for (var i = 2; i <= n; i++) r *= i
  return r
}

function parse(tokens) {
  var pos = 0
  function peek() { return tokens[pos] }
  function next() { return tokens[pos++] }
  function isOp(tok, v) { return tok && tok.t === "op" && tok.v === v }

  function expr() {
    var v = term()
    while (isOp(peek(), "+") || isOp(peek(), "-")) {
      var op = next().v
      var r = term()
      v = op === "+" ? v + r : v - r
    }
    return v
  }
  function startsAtom(tok) {
    return tok && (tok.t === "num" || tok.t === "word" || tok.t === "(")
  }
  function term() {
    var v = unary()
    for (;;) {
      var tok = peek()
      if (isOp(tok, "*")) { next(); v *= unary() }
      else if (isOp(tok, "/")) { next(); var d = unary(); if (d === 0) throw new Error("division by zero"); v /= d }
      else if (isOp(tok, "mod")) { next(); v %= unary() }
      else if (startsAtom(tok)) { v *= power() }   // implicit: 2pi, 3(4+1)
      else break
    }
    return v
  }
  function unary() {
    if (isOp(peek(), "-")) { next(); return -unary() }
    if (isOp(peek(), "+")) { next(); return unary() }
    return power()
  }
  function power() {
    var base = postfix()
    if (isOp(peek(), "^")) { next(); return Math.pow(base, unary()) }
    return base
  }
  function postfix() {
    var v = atom()
    for (;;) {
      if (isOp(peek(), "%")) { next(); v /= 100 }
      else if (isOp(peek(), "!")) { next(); v = factorial(v) }
      else break
    }
    return v
  }
  function atom() {
    var tok = next()
    if (!tok) throw new Error("unexpected end")
    if (tok.t === "num") return tok.v
    if (tok.t === "(") {
      var v = expr()
      if (!peek() || peek().t !== ")") throw new Error("missing )")
      next()
      return v
    }
    if (tok.t === "word") {
      if (FUNCTIONS[tok.v]) {
        if (!peek() || peek().t !== "(") throw new Error(tok.v + " needs (")
        next()
        var args = [expr()]
        while (peek() && peek().t === "sep") { next(); args.push(expr()) }
        if (!peek() || peek().t !== ")") throw new Error("missing )")
        next()
        return FUNCTIONS[tok.v].apply(null, args)
      }
      if (CONSTANTS[tok.v] !== undefined) return CONSTANTS[tok.v]
      throw new Error("unknown " + tok.v)
    }
    throw new Error("unexpected token")
  }

  var value = expr()
  if (pos < tokens.length) throw new Error("trailing input")
  return value
}

// True when the text is worth evaluating: it has a digit or constant and at
// least one operator or function, so "2026" or "firefox" stay quiet.
function looksLikeMath(text) {
  var s = String(text || "").trim()
  if (!s || s.length > 200) return false
  if (!/[\dπ]/.test(s) && !/\b(pi|tau|e)\b/i.test(s)) return false
  var words = s.toLowerCase().match(/[a-zπ]+/g) || []
  for (var i = 0; i < words.length; i++) {
    if (!FUNCTIONS[words[i]] && CONSTANTS[words[i]] === undefined && words[i] !== "mod" && words[i] !== "x") return false
  }
  // A known function or constant counts as math on its own ("2pi", "sqrt 2").
  if (words.some(function(w) { return w !== "x" })) return true
  return /[+\-*/^%!×÷()]|\bmod\b|\d\s*x\s*\d/i.test(s.replace(/^\s*-/, ""))
}

function evaluate(text) {
  if (!looksLikeMath(text)) return null
  try {
    var v = parse(tokenize(text))
    if (typeof v !== "number" || !isFinite(v)) return null
    return v
  } catch (e) {
    return null
  }
}

// Up to 12 significant digits, no float noise, no trailing zeros.
function format(v) {
  if (v === 0) return "0"
  var abs = Math.abs(v)
  if (abs >= 1e15 || abs < 1e-9) return v.toExponential(6).replace(/\.?0+e/, "e")
  var s = Number(v.toPrecision(12)).toString()
  return s
}

// Thousands separated with a narrow space for display: 1234567.5 → 1 234 567.5
function pretty(s) {
  var parts = String(s).split(".")
  if (/e/.test(s)) return s
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  return parts.join(".")
}

if (typeof module !== "undefined") {
  module.exports = { tokenize: tokenize, parse: parse, evaluate: evaluate, looksLikeMath: looksLikeMath, format: format, pretty: pretty }
}
