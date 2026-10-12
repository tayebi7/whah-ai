package com.wahaai.app

import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class ChatMessage(
    val content: String,
    val isUser: Boolean,
    val timestamp: Long = System.currentTimeMillis(),
    val isError: Boolean = false
)

class MessageAdapter(
    private val messages: MutableList<ChatMessage> = mutableListOf()
) : RecyclerView.Adapter<MessageAdapter.MessageViewHolder>() {

    class MessageViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val bubbleContainer: LinearLayout = view.findViewById(R.id.bubbleContainer)
        val textMessage: TextView = view.findViewById(R.id.textMessage)
        val textTime: TextView = view.findViewById(R.id.textTime)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MessageViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_message, parent, false)
        return MessageViewHolder(view)
    }

    override fun onBindViewHolder(holder: MessageViewHolder, position: Int) {
        val message = messages[position]
        val context = holder.itemView.context

        holder.textMessage.text = message.content
        val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
        holder.textTime.text = sdf.format(Date(message.timestamp))

        val params = holder.bubbleContainer.layoutParams as FrameLayout.LayoutParams
        if (message.isUser) {
            params.gravity = Gravity.END
            holder.bubbleContainer.setBackgroundResource(R.drawable.bg_message_user)
            holder.textMessage.setTextColor(context.getColor(R.color.user_bubble_text))
            holder.textTime.setTextColor(context.getColor(R.color.user_bubble_text))
        } else {
            params.gravity = Gravity.START
            holder.bubbleContainer.setBackgroundResource(R.drawable.bg_message_ai)
            val textColor = if (message.isError) context.getColor(R.color.error)
                            else context.getColor(R.color.ai_bubble_text)
            holder.textMessage.setTextColor(textColor)
            holder.textTime.setTextColor(context.getColor(R.color.ai_bubble_text))
        }
        holder.bubbleContainer.layoutParams = params
    }

    override fun getItemCount(): Int = messages.size

    fun addMessage(message: ChatMessage) {
        messages.add(message)
        notifyItemInserted(messages.size - 1)
    }

    fun removeLastMessage() {
        if (messages.isNotEmpty()) {
            messages.removeAt(messages.size - 1)
            notifyItemRemoved(messages.size)
        }
    }

    fun clearMessages() {
        val size = messages.size
        messages.clear()
        notifyItemRangeRemoved(0, size)
    }
}
