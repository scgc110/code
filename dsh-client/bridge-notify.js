// dsh-ntfy-bridge — host plugin: harness events -> in-memory state -> HTTP route
// dsh-client polls http://127.0.0.1:3080/dsh-notify.json and shows a balloon.
// No filesystem involved: the harness's own web server is the delivery channel.
'use strict'
module.exports = {
  apply(ctx) {
    const webServer = ctx.get('webServer')
    const state = { id: 0, last: null, counters: { approval: 0, question: 0, complete: 0, error: 0 } }

    function notify(type, title, body) {
      state.id += 1
      state.counters[type] = (state.counters[type] || 0) + 1
      state.last = { id: state.id, type, title, body: String(body || '').slice(0, 500), ts: Date.now() }
      console.log('ntfy: [' + state.id + '] ' + type + ' ' + title)
    }

    // approval needed (approval dialog)
    ctx.on('approval/request', (req, next) => {
      const msg = (req && (req.message || req.kind || req.action)) || 'approval request'
      notify('approval', '需要你的授权', String(msg))
      return next()
    })

    // user question asked (ask_user_question tool)
    ctx.on('tools/pre-execute', (exec, next) => {
      if (exec && exec.name === 'ask_user_question') {
        let q = ''
        try {
          const qs = exec.arguments && exec.arguments.questions
          if (qs && qs.length) q = String(qs[0].question || qs[0].header || '')
        } catch (e) { q = '' }
        notify('question', '需要你回答问题', q || 'waiting for your input')
      }
      return next()
    })

    // task complete (turn ended: running -> idle)
    ctx.on('agent/status', (payload) => {
      if (payload && payload.status === 'idle') {
        notify('complete', '任务完成', '回合已结束' + (payload.agent ? '（' + payload.agent.id + '）' : ''))
      }
    })

    // run error
    ctx.on('agent/error', (payload) => {
      const err = payload && payload.error
      notify('error', '运行出错', String(err && err.message ? err.message : err).slice(0, 300))
    })

    if (webServer) {
      webServer.register({
        kind: 'exact',
        path: '/dsh-notify.json',
        handler(req, res) {
          res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' })
          res.end(JSON.stringify({ id: state.id, last: state.last, counters: state.counters }))
        },
      })
      console.log('ntfy: route /dsh-notify.json registered')
    } else {
      console.log('ntfy: webServer unavailable')
    }
    console.log('ntfy: bridge started (route-based)')
  },
}
