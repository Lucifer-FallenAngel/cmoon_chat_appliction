const express = require('express');
require('dotenv').config();
const http = require('http');
const { Server } = require('socket.io');
const { Op } = require('sequelize');

const { connectDB } = require('./config/db');
const db = require('./models');
const Message = db.Message;

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: '*' },
});

app.use(express.json());
app.use('/uploads', express.static('uploads'));

app.use('/api/auth', require('./routes/auth_routes'));
app.use('/api/users', require('./routes/user_routes'));
app.use('/api/messages', require('./routes/message_routes'));

// ===============================
// ONLINE USERS MAP
// ===============================
let onlineUsers = {}; // userId -> socketId

io.on('connection', (socket) => {
  console.log('🟢 Socket connected:', socket.id);

  // ==================================================
  // USER ONLINE
  // ==================================================
  socket.on('user-online', (userId) => {
    if (!userId) return;

    onlineUsers[userId] = socket.id;

    io.emit('online-users', Object.keys(onlineUsers));
  });

  // ==================================================
  // SEND MESSAGE (NOTIFY RECEIVER)
  // ==================================================
  socket.on('send-message', (data) => {
    if (!data || !data.receiver_id) return;

    const receiverSocketId = onlineUsers[data.receiver_id];

    if (receiverSocketId) {
      io.to(receiverSocketId).emit('receive-message', {
        conversation_id: data.conversation_id,
        sender_id: data.sender_id,
        receiver_id: data.receiver_id,
      });
    }
  });

  // ==================================================
  // CHAT OPENED → MARK AS DELIVERED
  // ==================================================
  socket.on('chat-opened', async ({ senderId, receiverId }) => {
    try {
      await Message.update(
        { status: 'delivered' },
        {
          where: {
            sender_id: senderId,
            receiver_id: receiverId,
            status: 'sent',
          },
        }
      );

      const senderSocketId = onlineUsers[senderId];
      if (senderSocketId) {
        io.to(senderSocketId).emit('message-status-update', {
          senderId,
          receiverId,
          status: 'delivered',
        });
      }
    } catch (err) {
      console.error('❌ Delivered update error:', err);
    }
  });

  // ==================================================
  // MESSAGE READ
  // ==================================================
  socket.on('message-read', async ({ senderId, receiverId }) => {
    try {
      await Message.update(
        { status: 'read' },
        {
          where: {
            sender_id: senderId,
            receiver_id: receiverId,
            status: { [Op.ne]: 'read' },
          },
        }
      );

      const senderSocketId = onlineUsers[senderId];
      if (senderSocketId) {
        io.to(senderSocketId).emit('message-status-update', {
          senderId,
          receiverId,
          status: 'read',
        });
      }
    } catch (err) {
      console.error('❌ Read update error:', err);
    }
  });

  // ==================================================
  // DELETE FOR ME (SOCKET SYNC)
  // ==================================================
  socket.on('delete-for-me', ({ messageId, userId }) => {
    if (!messageId || !userId) return;

    // Only update UI for this user (not the other person)
    const socketId = onlineUsers[userId];
    if (socketId) {
      io.to(socketId).emit('message-deleted-for-me', {
        messageId,
      });
    }
  });

  // ==================================================
  // DISCONNECT
  // ==================================================
  socket.on('disconnect', () => {
    console.log('🔴 Socket disconnected:', socket.id);

    for (const userId of Object.keys(onlineUsers)) {
      if (onlineUsers[userId] === socket.id) {
        delete onlineUsers[userId];
        break;
      }
    }

    io.emit('online-users', Object.keys(onlineUsers));
  });
});

// ==================================================
// SERVER START
// ==================================================
const PORT = process.env.PORT || 5000;

(async () => {
  try {
    await connectDB();
    await db.sequelize.sync({ alter: true });

    server.listen(PORT, () => {
      console.log(`🚀 Server running on port ${PORT}`);
    });
  } catch (err) {
    console.error('❌ Server failed to start:', err);
  }
})();
