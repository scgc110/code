// dsh-client 通知桥接插件 v3（Host 半，动态 Cordis 插件）
// 文件通道：监听 harness 事件 → fs.writeText 写 D:\plan\dsh-client\notify.json
// → dsh-client 客户端定时轮询并弹系统气泡。零网络、零子进程，最稳。
return {
  apply(ctx) {
    const fs = ctx.get('fs')
    const NOTIFY_FILE = 'D:\\plan\\dsh-client\\notify.json'

    function notify(type, title, body) {
      if (fs === undefined) { console.log('ntfy: fs 不可用'); return }
      const payload = JSON.stringify({ type, title, body: String(body || '').slice(0, 500) })
      fs.resolve(NOTIFY_FILE)
        .then((target) => fs.writeText(target, payload))
        .then(() => console.log('ntfy: wrote ' + NOTIFY_FILE))
        .catch((e) => console.log('ntfy: write err ' + String((e && e.message) || e)))
    }

    // 需要授权（审批弹窗）
    ctx.on('approval/request', (req, next) => {
      const msg = (req && (req.message || req.kind || req.action)) || '审批请求'
      notify('approval', '需要你的授权', String(msg))
      return next()
    })

    // 需要回答问题（ask_user_question 工具被调用）
    ctx.on('tools/pre-execute', (exec, next) => {
      if (exec && exec.name === 'ask_user_question') {
        let q = ''
        try {
          const qs = exec.arguments && exec.arguments.questions
          if (qs && qs.length) q = String(qs[0].question || qs[0].header || '')
        } catch (e) { q = '' }
        notify('question', '需要你回答问题', q || '等待你的输入')
      }
      return next()
    })

    // 任务完成（回合结束：running → idle）
    ctx.on('agent/status', (payload) => {
      if (payload && payload.status === 'idle') {
        notify('complete', '任务完成', '回合已结束' + (payload.agent ? '（' + payload.agent.id + '）' : ''))
      }
    })

    // 运行出错
    ctx.on('agent/error', (payload) => {
      const err = payload && payload.error
      notify('error', '运行出错', String(err && err.message ? err.message : err).slice(0, 300))
    })

    console.log('ntfy: v3 文件通道桥接已启动')
  },
}