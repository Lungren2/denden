'use strict';
// The only things the page can ask of the system.
const { contextBridge, ipcRenderer } = require('electron');

const on = (channel) => (fn) => ipcRenderer.on(channel, (_e, data) => fn(data));

contextBridge.exposeInMainWorld('setup', {
  state: () => ipcRenderer.invoke('state'),
  backups: () => ipcRenderer.invoke('backups'),
  githubSignIn: () => ipcRenderer.invoke('github:sign-in'),
  tailscaleConnect: () => ipcRenderer.invoke('tailscale:connect'),
  backupsSetup: () => ipcRenderer.invoke('backups:setup'),
  open: (url) => ipcRenderer.invoke('open', url),
  copy: (text) => ipcRenderer.invoke('copy', text),
  resize: (height) => ipcRenderer.invoke('resize', height),
  close: () => ipcRenderer.invoke('close'),
  onGithubCode: on('github:code'),
  onGithubDone: on('github:done'),
  onTailscaleUrl: on('tailscale:url'),
  onTailscaleDone: on('tailscale:done'),
});
