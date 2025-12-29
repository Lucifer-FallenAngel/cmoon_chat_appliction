const express = require('express');
require('dotenv').config();
const http = require('http');
const { Server } = require('socket.io');
const { Op } = require('sequelize');
const OneSignal = require('onesignal-node'); // NEW: for push notifications

const { connectDB } = require('./config/db');
const db = require('./models');

const Message = db.Message;

const app = express();
const server = http.createServer(app);

/* ============================================================
   SOCKET.IO SETUP
============================================================ */
const io = new Server(server, {
  cors: { origin: '*' },
});

/* ============================================================
   ONESIGNAL PUSH NOTIFICATION CLIENT (NEW)
============================================================ */
const onesignalClient = new OneSignal.Client(
  process.env.ONESIGNAL_APP_ID,    // Add these to your .env
  process.env.ONESIGNAL_API_KEY
);
app.set('onesignalClient', onesignalClient); // Make available in routes

/* ============================================================
   ONLINE USERS MAP (userId → socketId)
============================================================ */
const onlineUsers = {};

// Make io & onlineUsers available in routes/middleware
app.set('io', io);
app.set('onlineUsers', onlineUsers);

/* ============================================================
   MIDDLEWARE
============================================================ */
app.use(express.json());
app.use('/uploads', express.static('uploads'));

/* ============================================================
   ROUTES
============================================================ */
app.use('/api/auth', require('./routes/auth_routes'));
app.use('/api/users', require('./routes/user_routes'));
app.use('/api/messages', require('./routes/message_routes'));

/* ============================================================
   SOCKET EVENTS
============================================================ */
io.on('connection', (socket) => {
  console.log('🟢 New connection:', socket.id);

  socket.on('user-online', (userId) => {
    if (!userId) return;

    onlineUsers[userId] = socket.id;
    io.emit('online-users-updated', Object.keys(onlineUsers));
    console.log(`User ${userId} is now online`);
  });

  socket.on('send-message', ({ sender_id, receiver_id }) => {
    if (!receiver_id) return;

    const receiverSocket = onlineUsers[receiver_id];
    if (receiverSocket) {
      io.to(receiverSocket).emit('new-message-arrived', {
        sender_id,
        receiver_id,
      });
    }
  });

  socket.on('chat-opened', async ({ senderId, receiverId }) => {
    try {
      const [updatedCount] = await Message.update(
        { status: 'delivered' },
        {
          where: {
            sender_id: senderId,
            receiver_id: receiverId,
            status: 'sent',
          },
        }
      );

      if (updatedCount > 0) {
        const senderSocket = onlineUsers[senderId];
        if (senderSocket) {
          io.to(senderSocket).emit('messages-delivered', {
            senderId,
            receiverId,
            status: 'delivered',
          });
        }
        console.log(`Marked ${updatedCount} messages as delivered`);
      }
    } catch (err) {
      console.error('❌ Error marking messages as delivered:', err);
    }
  });

  socket.on('messages-read', async ({ senderId, receiverId }) => {
    try {
      const [updatedCount] = await Message.update(
        { status: 'read' },
        {
          where: {
            sender_id: senderId,
            receiver_id: receiverId,
            status: { [Op.ne]: 'read' },
          },
        }
      );

      if (updatedCount > 0) {
        const senderSocket = onlineUsers[senderId];
        if (senderSocket) {
          io.to(senderSocket).emit('messages-read-by-recipient', {
            senderId,
            receiverId,
            status: 'read',
          });
        }
        console.log(`Marked ${updatedCount} messages as READ by ${receiverId}`);
      }
    } catch (err) {
      console.error('❌ Error marking messages as read:', err);
    }
  });

  socket.on('delete-for-me', ({ messageId, userId }) => {
    const socketId = onlineUsers[userId];
    if (socketId) {
      io.to(socketId).emit('message-deleted-for-me', { messageId, userId });
    }
  });

  socket.on('disconnect', () => {
    console.log('🔴 Disconnected:', socket.id);

    let disconnectedUserId = null;
    for (const uid in onlineUsers) {
      if (onlineUsers[uid] === socket.id) {
        disconnectedUserId = uid;
        delete onlineUsers[uid];
        break;
      }
    }

    if (disconnectedUserId) {
      io.emit('online-users-updated', Object.keys(onlineUsers));
      console.log(`User ${disconnectedUserId} went offline`);
    }
  });
});

/* ============================================================
   START SERVER
============================================================ */
const PORT = process.env.PORT || 5000;

(async () => {
  try {
    await connectDB();

    await db.sequelize.sync({ force: false });

    server.listen(PORT, () => {
      console.log(`🚀 Server running on port ${PORT}`);
    });
  } catch (err) {
    console.error('❌ Failed to start server:', err);
    process.exit(1);
  }
})();