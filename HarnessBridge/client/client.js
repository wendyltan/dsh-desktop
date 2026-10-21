window.__ModuleLoader__.load({
  id: 'dsh-desktop-bridge',
  factory: () => {
    const inject = ['uiWorkspace', 'sessions', 'layout', 'theme']
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
          const attemptId = event.detail?.attemptId
          if (typeof attemptId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/u.test(attemptId)) {
            acknowledgePanel({ panelId: typeof panelId === 'string' ? panelId : '', attemptId: '', opened: false, error: '插件管理页请求编号无效。' })
            return
          }
          if (panelId !== 'plugins') {
            acknowledgePanel({ panelId: typeof panelId === 'string' ? panelId : '', attemptId, opened: false, error: '只支持打开插件管理面板。' })
            return
          }
          try {
            Promise.resolve(ctx.layout.selectPanel('plugins')).then(
              () => acknowledgePanel({ panelId, attemptId, opened: true }),
              () => acknowledgePanel({ panelId, attemptId, opened: false, error: '无法打开插件管理面板，请在工作区中手动打开。' }),
            )
          } catch {
            acknowledgePanel({ panelId, attemptId, opened: false, error: '无法打开插件管理面板，请在工作区中手动打开。' })
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

      ctx.effect(() => {
        if (!window.webkit?.messageHandlers?.dshDesktopOpenSession) return
        return ctx.theme.overrideTokens(name, {
          '--dsw-alias-bg-base': { light: '#FFFFFF', dark: '#1E293B' },
          '--dsw-alias-bg-layer-1': { light: '#F5F7FF', dark: '#263449' },
          '--dsw-alias-bg-layer-2': { light: '#EAF0FF', dark: '#33435C' },
          '--dsw-alias-bg-overlay': { light: '#FFFFFF', dark: '#2D3B52' },
          '--dsw-alias-bg-module-platform': { light: '#F3F6FD', dark: '#33435C' },
          '--dsw-alias-border-l1': { light: '#D9E1F2', dark: '#3D4D66' },
          '--dsw-alias-border-l2': { light: '#BCCBE6', dark: '#51627D' },
          '--dsw-alias-brand-primary': { light: '#4162EA', dark: '#9BAEFF' },
          '--dsw-alias-button-primary-hover': { light: '#3554D4', dark: '#B1BFFF' },
          '--dsw-alias-button-info-fill': { light: '#4162EA', dark: '#4162EA' },
          '--dsw-alias-button-info-hover': { light: '#3554D4', dark: '#3554D4' },
          '--dsw-alias-interactive-bg-hover': { light: '#E7EDF8', dark: '#3D4D66' },
          '--dsw-alias-label-primary': { light: '#1F2A44', dark: '#F1F5FF' },
          '--dsw-alias-label-secondary': { light: '#596981', dark: '#C2CDE0' },
          '--dsw-alias-label-tertiary': { light: '#586780', dark: '#B9C7DD' },
          '--dsw-alias-label-caption': { light: '#586780', dark: '#B9C7DD' },
          '--dsw-specific-sidebar-fill': { light: '#F3F6FF', dark: '#222F45' },
          '--dsw-specific-sidebar-nav-item-active': { light: '#DEE7FF', dark: '#33435C' },
          '--dsw-specific-sidebar-nav-item-active-accent': { light: '#F1F5FF', dark: '#F1F5FF' },
          '--dsw-specific-input-major': { light: '#F2F5FB', dark: '#263449' },
          '--dsw-specific-bubble': { light: '#EAF0FF', dark: '#33435C' },
        })
      }, 'dsh-desktop-bridge: workspace appearance')
    }

    return { apply, inject, name }
  },
})
