window.__ModuleLoader__.load({
  id: 'dsh-desktop-bridge',
  factory: () => {
    const inject = ['uiWorkspace', 'sessions', 'layout']
    const name = 'dsh-desktop-bridge'

    function apply(ctx) {
      ctx.effect(() => {
        const handler = window.webkit?.messageHandlers?.dshDesktopOpenSession
        const panelHandler = window.webkit?.messageHandlers?.dshDesktopOpenPanel
        const acknowledge = (body) => handler?.postMessage(body)
        const acknowledgePanel = (body) => panelHandler?.postMessage(body)
        let disposePending

        const openSession = (event) => {
          const sessionId = event.detail?.sessionId
          if (typeof sessionId !== 'string' || sessionId.length === 0 || sessionId.length > 256 || /[\u0000-\u001f\u007f]/u.test(sessionId)) {
            acknowledge({ sessionId: typeof sessionId === 'string' ? sessionId : '', opened: false, error: '任务会话编号无效。' })
            return
          }
          disposePending?.('任务定位请求已被新的请求取代。')
          let finished = false
          let unsubscribe = () => {}
          let timer
          const finish = (error) => {
            if (finished) return
            finished = true
            clearTimeout(timer)
            unsubscribe()
            if (disposePending === cancel) disposePending = undefined
            acknowledge(error
              ? { sessionId, opened: false, error }
              : { sessionId, opened: true })
          }
          const cancel = (error) => finish(error)
          disposePending = cancel
          timer = setTimeout(() => finish('打开任务等待超时，请确认侧栏中仍有此会话。'), 10000)
          let opened = false
          const checkSelection = () => {
            if (finished) return
            try {
              const list = ctx.sessions.list.getSnapshot()
              if (!opened) {
                if (list.phase !== 'ready') return
                if (!list.ids.includes(sessionId)) {
                  finish('该任务会话已不存在，请从侧栏确认。')
                  return
                }
                opened = true
                ctx.uiWorkspace.openSession(sessionId)
              }
              // The official catalog exposes main-view ownership, not a `current` field.
              if ((ctx.sessions.list.getSnapshot().byId[sessionId]?.retainedBy.mainView ?? 0) > 0) finish()
            } catch {
              finish('无法打开指定任务，请从侧栏确认该会话是否存在。')
            }
          }
          unsubscribe = ctx.sessions.list.subscribe(checkSelection)
          checkSelection()
        }

        const openPanel = (event) => {
          const panelId = event.detail?.panelId
          if (panelId !== 'plugins') {
            acknowledgePanel({ panelId: typeof panelId === 'string' ? panelId : '', opened: false, error: '只支持打开插件管理面板。' })
            return
          }
          try {
            Promise.resolve(ctx.layout.selectPanel('plugins')).then(
              () => acknowledgePanel({ panelId, opened: true }),
              () => acknowledgePanel({ panelId, opened: false, error: '无法打开插件管理面板，请在工作区中手动打开。' }),
            )
          } catch {
            acknowledgePanel({ panelId, opened: false, error: '无法打开插件管理面板，请在工作区中手动打开。' })
          }
        }

        window.addEventListener('dsh-desktop-open-session', openSession)
        window.addEventListener('dsh-desktop-open-panel', openPanel)
        acknowledge({ ready: true })
        acknowledgePanel({ ready: true })
        return () => {
          window.removeEventListener('dsh-desktop-open-session', openSession)
          window.removeEventListener('dsh-desktop-open-panel', openPanel)
          disposePending?.('客户端页面已关闭，任务定位未完成。')
        }
      }, 'dsh-desktop-bridge: session navigation')
    }

    return { apply, inject, name }
  },
})
