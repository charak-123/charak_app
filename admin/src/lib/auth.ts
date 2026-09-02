export const isAuthed = () => !!localStorage.getItem('charak_admin_token')
export const setToken = (t: string) => localStorage.setItem('charak_admin_token', t)
export const clearToken = () => localStorage.removeItem('charak_admin_token')
