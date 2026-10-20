const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const S = require(path.join(__dirname, "..", "plugins", "ssh", "Ssh.js"))

test("ssh: config hosts", () => {
  const cfg = "Host *\n  User nobody\nHost forge forge2  # comment\n  HostName 10.0.0.2\n  User me\n  Port 2222\nMatch host x\n  User y\nHost web\nHostName=web.example.com\nHost forge\n  User dup\n"
  assert.deepStrictEqual(S.hosts(cfg), [
    { name: "forge", hostname: "10.0.0.2", user: "me", port: "2222" },
    { name: "forge2", hostname: "10.0.0.2", user: "me", port: "2222" },
    { name: "web", hostname: "web.example.com", user: "", port: "" }
  ])
  assert.deepStrictEqual(S.termsFrom("ssh Forge"), ["forge"])
  assert.deepStrictEqual(S.termsFrom("ssh"), [])
  assert.strictEqual(S.termsFrom("sshfs"), null)
})
