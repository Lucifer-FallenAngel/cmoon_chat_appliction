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
        // For text messages
        type: DataTypes.TEXT,
        allowNull: true,
      },

      message_type: {
        type: DataTypes.ENUM('text', 'image', 'file'),
        allowNull: false,
        defaultValue: 'text',
      },

      file_url: {
        // For image/file messages
        type: DataTypes.STRING,
        allowNull: true,
      },

      status: {
        // sent → delivered → read
        type: DataTypes.ENUM('sent', 'delivered', 'read'),
        allowNull: false,
        defaultValue: 'sent',
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
