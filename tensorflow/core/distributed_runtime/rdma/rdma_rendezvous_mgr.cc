// Copyright 2017 Yahoo Inc.
// Licensed under the terms of the Apache 2.0 license.
// Please see LICENSE file in the project root for terms.

#include <unordered_set>

#include "tensorflow/core/common_runtime/device.h"
#include "tensorflow/core/common_runtime/device_mgr.h"
#include "tensorflow/core/common_runtime/dma_helper.h"
#include "tensorflow/core/distributed_runtime/rdma/rdma.h"
#include "tensorflow/core/distributed_runtime/rdma/rdma_mgr.h"
#include "tensorflow/core/distributed_runtime/rdma/rdma_rendezvous_mgr.h"
#include "tensorflow/core/lib/core/errors.h"
#include "tensorflow/core/lib/strings/numbers.h"
#include "tensorflow/core/lib/strings/str_util.h"

namespace tensorflow {

class RdmaRemoteRendezvous : public BaseRemoteRendezvous {
 public:
  RdmaRemoteRendezvous(const WorkerEnv* env, int64 step_id)
      : BaseRemoteRendezvous(env, step_id, true) {}

 protected:
  void RecvFromRemoteAsync(const Rendezvous::ParsedKey& parsed,
                           const Rendezvous::Args& args,
                           DoneCallback done) override;
 private:
  ~RdmaRemoteRendezvous() override {}

  TF_DISALLOW_COPY_AND_ASSIGN(RdmaRemoteRendezvous);
};

void RdmaRemoteRendezvous::RecvFromRemoteAsync(
    const Rendezvous::ParsedKey& parsed, const Rendezvous::Args& recv_args, 
    DoneCallback done) { 
  Status s;
  // parse src_name and dst_name
  string src_name, dst_name, unused;
  if (!DeviceNameUtils::SplitDeviceName(parsed.src_device,
                                        &src_name, &unused)) {
    s = errors::Internal("Could not parse src name.");
  }
  CHECK(s.ok()) << "s is not ok, error code " << s.error_message();
  if (!s.ok()) {
    done(s, Args(), recv_args, Tensor{}, false);
    return;
  }
  if (!DeviceNameUtils::SplitDeviceName(parsed.dst_device,
                                        &dst_name, &unused)) {
    s = errors::Internal("Could not parse dst name.");
  }
  CHECK(s.ok()) << "s is not ok, error code " << s.error_message();
  if (!s.ok()) {
    done(s, Args(), recv_args, Tensor{}, false);
    return;
  }
  CHECK(dst_name.compare(env_->rdma_mgr->local_worker()) == 0);
  RdmaChannel* rc = env_->rdma_mgr->FindChannel(src_name);
  string key(std::move(parsed.FullKey().ToString()));
  string key_with_step_id = AppendStepidToKey(key, step_id_);
  // insert callback
  rc->InsertRecvCallback(key_with_step_id, 
    [this, key, key_with_step_id, rc, recv_args, parsed, done](){
      Status s;     
      Device* src_dev;
      s = env_->device_mgr->LookupDevice("CPU:0", &src_dev);
      CHECK(s.ok()) << "s is not ok, error code " << s.error_message();
      if (!s.ok()) {
        done(s, Args(), recv_args, Tensor(), true);
        return;
      }
      Device* dst_dev;
      s = env_->device_mgr->LookupDevice(parsed.dst_device, &dst_dev);
      CHECK(s.ok()) << "s is not ok, error code " << s.error_message();
      if (!s.ok()) {
        done(s, Args(), recv_args, Tensor(), true);
        return;
      }
      AllocatorAttributes src_alloc_attr;
      src_alloc_attr.set_on_host(true);
      DeviceContext* src_dev_context = nullptr;              
      RdmaBuffer* rb = rc->FindBuffer(key);
      RdmaMessage rm;
      CHECK(rb->size_ >= RdmaMessage::kMessageTotalBytes);
      RdmaMessage::ParseMessage(rm, rb->buffer_);
      CHECK(rm.type_ == RDMA_MESSAGE_TENSOR_WRITE);
      Tensor val;
      if (!rm.is_dead_) {
        void* input = static_cast<char*>(rb->buffer_) + 
              RdmaMessage::kTensorBufferStartIndex;
        TensorProto proto;
        CHECK(rm.tensor_bytes_ + RdmaMessage::kTensorBufferStartIndex <= rb->size_);
        CHECK(proto.ParseFromArray(input, rm.tensor_bytes_))
                << "proto parse from array";
        s = dst_dev->MakeTensorFromProto(proto,
                       recv_args.alloc_attrs, &val);
      }
      
      rc->RemoveRecvCallback(key_with_step_id);
      // create message
      RdmaMessage br;
      br.type_ = RDMA_MESSAGE_BUFFER_IDLE;
      br.name_size_ = key.size();
      br.name_ = key;
      string message = RdmaMessage::CreateMessage(br);
      RdmaBuffer* tb = rc->tx_message_buffer_;
      tb->EnqueueItem(message); 
      tb->SendNextItem();
      done(s, Args(), recv_args, val, rm.is_dead_);
    });
  // append key to message queue
  RdmaBuffer* rb = rc->tx_message_buffer_;
  RdmaMessage rm;
  rm.type_ = RDMA_MESSAGE_TENSOR_REQUEST;
  rm.name_size_ = key.size();
  rm.name_ = key;
  rm.step_id_ = step_id_;
  string message = RdmaMessage::CreateMessage(rm);
  rb->EnqueueItem(message);
  rb->SendNextItem();
}

RdmaRendezvousMgr::RdmaRendezvousMgr(const WorkerEnv* env)
    : BaseRendezvousMgr(env) {}

BaseRemoteRendezvous* RdmaRendezvousMgr::Create(int64 step_id,
                                                const WorkerEnv* worker_env) {
  return new RdmaRemoteRendezvous(worker_env, step_id);
}

}  // end namespace tensorflow
