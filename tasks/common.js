const util = require("util");
const request = util.promisify(require("request"));

module.exports.factoryAddress = "0x2b5a0aEE56c23Bed338e4f6B1048b9fA213d97B3";
module.exports.planAddress = "0xC2b96D57f8928502e3838CdEa94F570B86fb644D";

module.exports.callRpc = async function(method, params) {
    var options = {
      method: "POST",
      url: "https://api.hyperspace.node.glif.io/rpc/v1",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: 1,
      }),
    };
    const res = await request(options);
    return JSON.parse(res.body).result;
}