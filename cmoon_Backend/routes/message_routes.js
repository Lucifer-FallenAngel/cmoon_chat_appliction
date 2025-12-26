const express = require('express');
const { Op } = require('sequelize');
const db = require('../models');

const router = express.Router();

const Message = db.Message;
const Conversation = db.Conversation;
const BlockedUser = db.BlockedUser;

/* ============================================================
   SEND MESSAGE
============================================================ */
router.post('/send', async (req, res) => {
  try {
    const { sender_id, receiver_id, message } = req.body;

    if (!sender_id || !receiver_id || !message) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

    // 🚫 CHECK BLOCK (both directions)
    const blocked = await BlockedUser.findOne({
      where: {
        [Op.or]: [
          { blocker_id: sender_id, blocked_id: receiver_id },
          { blocker_id: receiver_id, blocked_id: sender_id },
        ],
      },
    });

    if (blocked) {
      return res.status(403).json({ message: 'User is blocked' });
    }

    // 🔎 FIND OR CREATE CONVERSATION
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

    // 💾 CREATE MESSAGE
    const msg = await Message.create({
      conversation_id: convo.id,
      sender_id,
      receiver_id,
      message,
      status: 'sent',
      deleted_for: [],
    });

    res.json(msg);
  } catch (err) {
    console.error('SEND MESSAGE ERROR:', err);
    res.sendStatus(500);
  }
});

/* ============================================================
   LOAD CHAT (FILTER DELETE-FOR-ME)
============================================================ */
router.get('/:user1/:user2', async (req, res) => {
  try {
    const user1 = parseInt(req.params.user1);
    const user2 = parseInt(req.params.user2);

    const convo = await Conversation.findOne({
      where: {
        [Op.or]: [
          { user1_id: user1, user2_id: user2 },
          { user1_id: user2, user2_id: user1 },
        ],
      },
    });

    if (!convo) return res.json([]);

    const allMessages = await Message.findAll({
      where: { conversation_id: convo.id },
      order: [['createdAt', 'ASC']],
    });

    // ✅ FILTER DELETED MESSAGES FOR CURRENT USER
    const visibleMessages = allMessages.filter((msg) => {
      const deletedFor = Array.isArray(msg.deleted_for)
        ? msg.deleted_for
        : [];
      return !deletedFor.includes(user1);
    });

    // ✅ MARK AS DELIVERED
    await Message.update(
      { status: 'delivered' },
      {
        where: {
          conversation_id: convo.id,
          sender_id: user2,
          receiver_id: user1,
          status: 'sent',
        },
      }
    );

    res.json(visibleMessages);
  } catch (err) {
    console.error('LOAD CHAT ERROR:', err);
    res.sendStatus(500);
  }
});

/* ============================================================
   MARK ALL AS READ
============================================================ */
router.post('/read-all', async (req, res) => {
  try {
    const { sender_id, receiver_id } = req.body;

    await Message.update(
      { status: 'read' },
      {
        where: {
          sender_id,
          receiver_id,
          status: { [Op.ne]: 'read' },
        },
      }
    );

    res.sendStatus(200);
  } catch (err) {
    console.error('READ ALL ERROR:', err);
    res.sendStatus(500);
  }
});

/* ============================================================
   DELETE FOR ME
============================================================ */
router.post('/delete-for-me', async (req, res) => {
  try {
    const { messageId, userId } = req.body;

    if (!messageId || !userId) {
      return res.status(400).json({ message: 'Missing parameters' });
    }

    const msg = await Message.findByPk(messageId);
    if (!msg) return res.sendStatus(404);

    const deletedFor = Array.isArray(msg.deleted_for)
      ? msg.deleted_for
      : [];

    if (!deletedFor.includes(userId)) {
      deletedFor.push(userId);
      await msg.update({ deleted_for: deletedFor });
    }

    res.sendStatus(200);
  } catch (err) {
    console.error('DELETE FOR ME ERROR:', err);
    res.sendStatus(500);
  }
});

/* ============================================================
   CLEAR CHAT (DELETE ALL FOR USER)
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

    if (!convo) return res.sendStatus(200);

    const messages = await Message.findAll({
      where: { conversation_id: convo.id },
    });

    for (const msg of messages) {
      const deletedFor = Array.isArray(msg.deleted_for)
        ? msg.deleted_for
        : [];

      if (!deletedFor.includes(userId)) {
        deletedFor.push(userId);
        await msg.update({ deleted_for: deletedFor });
      }
    }

    res.sendStatus(200);
  } catch (err) {
    console.error('CLEAR CHAT ERROR:', err);
    res.sendStatus(500);
  }
});

/* ============================================================
   BLOCK USER
============================================================ */
router.post('/block', async (req, res) => {
  try {
    const { blocker_id, blocked_id } = req.body;

    if (!blocker_id || !blocked_id) {
      return res.status(400).json({ message: 'Missing parameters' });
    }

    const exists = await BlockedUser.findOne({
      where: { blocker_id, blocked_id },
    });

    if (!exists) {
      await BlockedUser.create({ blocker_id, blocked_id });
    }

    res.sendStatus(200);
  } catch (err) {
    console.error('BLOCK USER ERROR:', err);
    res.sendStatus(500);
  }
});

/* ============================================================
   UNBLOCK USER
============================================================ */
router.post('/unblock', async (req, res) => {
  try {
    const { blocker_id, blocked_id } = req.body;

    if (!blocker_id || !blocked_id) {
      return res.status(400).json({ message: 'Missing parameters' });
    }

    await BlockedUser.destroy({
      where: { blocker_id, blocked_id },
    });

    res.sendStatus(200);
  } catch (err) {
    console.error('UNBLOCK USER ERROR:', err);
    res.sendStatus(500);
  }
});

/* ============================================================
   CHECK BLOCK STATUS
============================================================ */
router.get('/is-blocked/:me/:other', async (req, res) => {
  try {
    const { me, other } = req.params;

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
    console.error('CHECK BLOCK ERROR:', err);
    res.sendStatus(500);
  }
});

module.exports = router;
