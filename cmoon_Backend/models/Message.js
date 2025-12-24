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
        defaultValue: 'text',
      },

      file_url: {
        type: DataTypes.STRING,
        allowNull: true,
      },

      status: {
        // sent → delivered → read
        type: DataTypes.ENUM('sent', 'delivered', 'read'),
        defaultValue: 'sent',
      },
    },
    {
      tableName: 'messages',
      timestamps: true,
    }
  );

  return Message;
};
