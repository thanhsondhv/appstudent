// static/js/chat_features.js

window.selectedMessages = new Set();
window.isSelectionMode = false;

window.addReaction = async function(msgId, emoji) {
    const activeGroupId = window.groupId || document.getElementById('target-group-id')?.value;
    await window.db.collection("groups").doc(activeGroupId).collection("messages").doc(msgId).update({
        [`reactions.${window.userId}`]: emoji
    });
};

window.copyMessage = function(text) {
    navigator.clipboard.writeText(text).then(() => alert("📋 Đã sao chép!"));
};

window.toggleSelectionMode = function() {
    window.isSelectionMode = !window.isSelectionMode;
    const bar = document.getElementById('bulk-action-bar');
    if (bar) bar.classList.toggle('hidden', !window.isSelectionMode);
    window.selectedMessages.clear();
    window.loadMessages(); // Vẽ lại để hiện checkbox
};

window.selectMessage = function(msgId) {
    if (window.selectedMessages.has(msgId)) window.selectedMessages.delete(msgId);
    else window.selectedMessages.add(msgId);
    const countEl = document.getElementById('selected-count');
    if (countEl) countEl.innerText = window.selectedMessages.size;
};