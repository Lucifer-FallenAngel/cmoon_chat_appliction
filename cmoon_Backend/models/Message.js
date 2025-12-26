const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  const Message = sequelize.define(
    'Message',
    {
      id: {
        type: DataTypes.INTEGER,
        autoIncrement: true,
        primaryKey: true,
      },

      conversation_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },

      sender_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },

      receiver_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },

      message: {
        type: DataTypes.TEXT,
        allowNull: true,
      },

      message_type: {
        type: DataTypes.ENUM('text', 'image', 'file'),
        allowNull: false,
        defaultValue: 'text',
      },

      file_url: {
        type: DataTypes.STRING,
        allowNull: true,
      },

      status: {
        type: DataTypes.ENUM('sent', 'delivered', 'read'),
        allowNull: false,
        defaultValue: 'sent',
      },

      // ✅ NEW FIELD — used for "Delete for Me"
      deleted_for: {
        type: DataTypes.JSON,
        allowNull: false,
        defaultValue: [],
      },
    },
    {
      tableName: 'messages',
      timestamps: true,

      indexes: [
        {
          name: 'idx_conversation_messages',
          fields: ['conversation_id'],
        },
        {
          name: 'idx_sender_receiver',
          fields: ['sender_id', 'receiver_id'],
        },
        {
          name: 'idx_message_status',
          fields: ['status'],
        },
      ],
    }
  );

  return Message;
};
