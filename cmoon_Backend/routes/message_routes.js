const express = require('express');
const { Op } = require('sequelize');
const multer = require('multer');
const path = require('path');
const db = require('../models');

const router = express.Router();

const Message = db.Message;
const Conversation = db.Conversation;
const BlockedUser = db.BlockedUser;
const User = db.User; // added for receiver lookup

/* ============================================================
   MULTER CONFIG for file uploads
============================================================ */
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/'),
  filename: (req, file, cb) =>
    cb(null, `${Date.now()}-${file.originalname}`),
});

const upload = multer({ storage });

/* ============================================================
   SEND TEXT MESSAGE
============================================================ */
router.post('/send', async (req, res) => {
  try {
    const { sender_id, receiver_id, message } = req.body;

    if (!sender_id || !receiver_id || !message)
      return res.status(400).json({ message: 'Missing fields' });

    const blocked = await BlockedUser.findOne({
      where: {
        [Op.or]: [
          { blocker_id: sender_id, blocked_id: receiver_id },
          { blocker_id: receiver_id, blocked_id: sender_id },
        ],
      },
    });

    if (blocked) return res.status(403).json({ message: 'User blocked' });

    let convo = await Conversation.findOne({
      where: {
        [Op.or]: [
          { user1_id: sender_id, user2_id: receiver_id },
          { user1_id: receiver_id, user2_id: sender_id },
        ],
      },
    });

    if (!convo) {
      convo = await Conversation.create({
        user1_id: sender_id,
        user2_id: receiver_id,
      });
    }

    const msg = await Message.create({
      conversation_id: convo.id,
      sender_id,
      receiver_id,
      message,
      message_type: 'text',
      status: 'sent',
      deleted_for: [],
    });

    const io = req.app.get('io');
    const onlineUsers = req.app.get('onlineUsers');

    // Check if receiver is offline → send push notification
    if (!onlineUsers[receiver_id]) {
      const receiver = await User.findByPk(receiver_id);
      if (receiver && receiver.onesignal_player_id) {
        const notification = {
          contents: {
            en: message.length > 100 ? `${message.substring(0, 97)}...` : message,
          },
          headings: { en: `New message from ${sender_id}` },
          include_player_ids: [receiver.onesignal_player_id],
          data: { senderId: sender_id.toString(), type: 'text' },
        };

        req.app.get('onesignalClient').createNotification(notification)
          .catch(err => console.error('Push notification failed:', err));
      }
    }

    if (onlineUsers[receiver_id]) {
      io.to(onlineUsers[receiver_id]).emit('new-message-arrived', {
        sender_id,
        receiver_id,
      });
    }

    res.json(msg);
  } catch (err) {
    console.error('SEND MESSAGE ERROR:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/* ============================================================
   UPLOAD IMAGE / FILE
============================================================ */
router.post('/upload', upload.single('file'), async (req, res) => {
  try {
    const { sender_id, receiver_id, message_type } = req.body;

    if (!req.file || !sender_id || !receiver_id || !message_type)
      return res.status(400).json({ message: 'Missing fields' });

    const blocked = await BlockedUser.findOne({
      where: {
        [Op.or]: [
          { blocker_id: sender_id, blocked_id: receiver_id },
          { blocker_id: receiver_id, blocked_id: sender_id },
        ],
      },
    });

    if (blocked) return res.status(403).json({ message: 'User blocked' });

    let convo = await Conversation.findOne({
      where: {
        [Op.or]: [
          { user1_id: sender_id, user2_id: receiver_id },
          { user1_id: receiver_id, user2_id: sender_id },
        ],
      },
    });

    if (!convo) {
      convo = await Conversation.create({
        user1_id: sender_id,
        user2_id: receiver_id,
      });
    }

    const msg = await Message.create({
      conversation_id: convo.id,
      sender_id,
      receiver_id,
      message_type,
      file_url: `uploads/${req.file.filename}`,
      status: 'sent',
      deleted_for: [],
    });

    const io = req.app.get('io');
    const onlineUsers = req.app.get('onlineUsers');

    // Check if receiver is offline → send push notification
    if (!onlineUsers[receiver_id]) {
      const receiver = await User.findByPk(receiver_id);
      if (receiver && receiver.onesignal_player_id) {
        const notificationBody = message_type === 'image' ? 'sent a photo' : 'sent a file';
        const notification = {
          contents: { en: notificationBody },
          headings: { en: `New message from ${sender_id}` },
          include_player_ids: [receiver.onesignal_player_id],
          data: { senderId: sender_id.toString(), type: message_type },
        };

        req.app.get('onesignalClient').createNotification(notification)
          .catch(err => console.error('Push notification failed:', err));
      }
    }

    if (onlineUsers[receiver_id]) {
      io.to(onlineUsers[receiver_id]).emit('new-message-arrived', {
        sender_id,
        receiver_id,
      });
    }

    res.json(msg);
  } catch (err) {
    console.error('UPLOAD ERROR:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/* ============================================================
   LOAD CHAT HISTORY
============================================================ */
router.get('/:myId/:otherId', async (req, res) => {
  try {
    const myId = parseInt(req.params.myId);
    const otherId = parseInt(req.params.otherId);

    const convo = await Conversation.findOne({
      where: {
        [Op.or]: [
          { user1_id: myId, user2_id: otherId },
          { user1_id: otherId, user2_id: myId },
        ],
      },
    });

    if (!convo) return res.json([]);

    const messages = await Message.findAll({
      where: {
        conversation_id: convo.id,
        deleted_for: {
          [Op.not]: { [Op.contains]: [myId] },
        },
      },
      order: [['createdAt', 'ASC']],
    });

    await Message.update(
      { status: 'delivered' },
      {
        where: {
          conversation_id: convo.id,
          sender_id: otherId,
          receiver_id: myId,
          status: 'sent',
        },
      }
    );

    res.json(messages);
  } catch (err) {
    console.error('LOAD CHAT ERROR:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/* ============================================================
   DELETE FOR ME
============================================================ */
router.post('/delete-for-me', async (req, res) => {
  try {
    const { messageId, userId } = req.body;

    const message = await Message.findByPk(messageId);
    if (!message) return res.status(404).json({ message: 'Message not found' });

    let deletedFor = Array.isArray(message.deleted_for) ? message.deleted_for : [];

    if (!deletedFor.includes(userId)) {
      deletedFor.push(userId);
      await message.update({ deleted_for: deletedFor });
    }

    const io = req.app.get('io');
    const onlineUsers = req.app.get('onlineUsers');
    const userSocket = onlineUsers[userId];

    if (userSocket) {
      io.to(userSocket).emit('message-deleted-for-me', { messageId });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('DELETE FOR ME ERROR:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/* ============================================================
   CLEAR CHAT
============================================================ */
router.post('/clear-chat', async (req, res) => {
  try {
    const { userId, otherUserId } = req.body;

    const convo = await Conversation.findOne({
      where: {
        [Op.or]: [
          { user1_id: userId, user2_id: otherUserId },
          { user1_id: otherUserId, user2_id: userId },
        ],
      },
    });

    if (!convo) return res.json({ success: true });

    const messages = await Message.findAll({
      where: { conversation_id: convo.id },
    });

    for (const msg of messages) {
      let deletedFor = Array.isArray(msg.deleted_for) ? msg.deleted_for : [];
      if (!deletedFor.includes(userId)) {
        deletedFor.push(userId);
        await msg.update({ deleted_for: deletedFor });
      }
    }

    const io = req.app.get('io');
    const onlineUsers = req.app.get('onlineUsers');
    const userSocket = onlineUsers[userId];

    if (userSocket) {
      io.to(userSocket).emit('chat-cleared-for-me', { otherUserId });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('CLEAR CHAT ERROR:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/* ============================================================
   BLOCK / UNBLOCK
============================================================ */
router.post('/block', async (req, res) => {
  const { blocker_id, blocked_id } = req.body;

  if (!blocker_id || !blocked_id)
    return res.status(400).json({ message: 'Missing params' });

  await BlockedUser.findOrCreate({
    where: { blocker_id, blocked_id },
  });

  res.json({ success: true });
});

router.post('/unblock', async (req, res) => {
  const { blocker_id, blocked_id } = req.body;

  await BlockedUser.destroy({
    where: { blocker_id, blocked_id },
  });

  res.json({ success: true });
});

/* ============================================================
   CHECK BLOCK STATUS
============================================================ */
router.get('/is-blocked/:me/:other', async (req, res) => {
  try {
    const me = parseInt(req.params.me);
    const other = parseInt(req.params.other);

    const iBlocked = await BlockedUser.findOne({
      where: { blocker_id: me, blocked_id: other },
    });

    const theyBlocked = await BlockedUser.findOne({
      where: { blocker_id: other, blocked_id: me },
    });

    res.json({
      blocked: !!(iBlocked || theyBlocked),
      iBlocked: !!iBlocked,
    });
  } catch (err) {
    console.error('BLOCK STATUS ERROR:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;