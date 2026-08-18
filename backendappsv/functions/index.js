const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios'); 

admin.initializeApp();

exports.onNewChatMessage = functions.firestore
    .document('groups/{groupId}/messages/{messageId}')
    .onCreate(async (snapshot, context) => {
        const msg = snapshot.data();
        const groupId = context.params.groupId;

        try {
            // 1. Lấy danh sách thành viên trong nhóm từ Firestore
            const groupDoc = await admin.firestore().doc(`groups/${groupId}`).get();
            if (!groupDoc.exists) return null;

            const members = groupDoc.data().members || [];

            // 2. Duyệt danh sách để tìm người nhận (người không phải người gửi)
            for (const uid of members) {
                if (uid !== msg.senderId) {
                    
                    // 🔥 GỌI VỀ SERVER CỦA SƠN ĐỂ ĐẨY VÀO HÀNG ĐỢI SQL SERVER
                    // Chúng ta truyền "Category: CHAT" và "Priority: 10" để đi làn q_high
                    const WEB_API_URL = 'https://mobi.vinhuni.edu.vn/api/chat/send-notification';

						// Trong hàm onCreate:
						await axios.post(WEB_API_URL, {
							sender_name: msg.senderName,
							receiver_id: uid,
							message_text: msg.text,
							group_id: groupId
						});

                    console.log(`🚀 Đã chuyển tiếp tin nhắn tới hàng đợi cho: ${uid}`);
                }
            }
        } catch (e) {
            console.error("❌ Lỗi Cloud Function:", e.message);
        }
        return null;
    });