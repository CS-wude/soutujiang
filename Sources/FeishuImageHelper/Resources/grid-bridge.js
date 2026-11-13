document.addEventListener('click', event => {
  if (!event.isTrusted) return;
  const button = event.target instanceof Element ? event.target.closest('[data-action]') : null;
  if (!button) return;
  window.webkit.messageHandlers.gridAction.postMessage({action: button.dataset.action, index: Number(button.dataset.index), generation: button.dataset.generation});
}, true);
