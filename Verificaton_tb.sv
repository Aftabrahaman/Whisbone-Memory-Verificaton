class transaction;
  rand bit [1:0] mode;
  rand bit strb;
  rand bit wr;
  rand bit [7:0] addr;
  rand bit [7:0] wdata;
  bit [7:0] rdata;
  bit ack;
  
  constraint mode_c{ mode >=0; mode<3;}
  constraint wdata_c{ wdata >=0 ; wdata <8;}
  constraint addr_c { addr==5;}
  
  function transaction copy();
    copy=new();
    copy.mode=this.mode;
    copy.strb=this.strb;
    copy.wr=this.wr;
    copy.addr=this.addr;
    copy.wdata=this.wdata;
    copy.rdata=this.rdata;
    copy.ack=this.ack;
  endfunction
  
  function void display(input string tag);
    $display("[%0s] : MODE : %0d  STRB : %0b  WR :%0b  ADdrs : %0d  Wdata : %0d  Radta : %0d   ack : %0b  ", tag,mode, strb,wr,addr,wdata,rdata,ack);
  endfunction
endclass

///////////////////////////////////////////////////////////////////////////////////////////////////////////


class generator;
  
  transaction tr;
  
  mailbox #(transaction) mbxgd;
  
  event done;
  event drvnext;
  event sconext;
  
  int count =0;
  
  function new(mailbox #(transaction) mbxgd);
    this.mbxgd=mbxgd;
    tr=new();
  endfunction

  task run();
    for(int i=0;i< count;i++)begin
      assert(tr.randomize) else $error("Randomization failed");
      tr.display("Gen");
      mbxgd.put(tr.copy);
      @drvnext;
      @sconext;
    end
    ->done;
  endtask
endclass

///////////////////////////////////////////////////////////////////////////////////////////////////////////

class driver;
  transaction tr;
  event drvnext;
  virtual wb_if vif;
  
  mailbox #(transaction) mbxgd;
  
  function new( mailbox #(transaction) mbxgd);
    this.mbxgd=mbxgd;
    endfunction
 
  task reset();
    vif.rst<=1'b1;
    vif.strb<=1'b0;
    vif.wdata<=8'h00;
    vif.wr<=0;
    vif.addr<=0;
    repeat(5)@(posedge vif.clk);
      vif.rst<=1'b0;
    repeat(5)@(posedge vif.clk);
      $display("[DRV] : Reset is done");
  endtask
  
  task write();
    @(posedge vif.clk);
    vif.rst<=1'b0;
    vif.strb<=1'b1;
    vif.wr<=1'b1;
    vif.addr<=tr.addr;
    vif.wdata<=tr.wdata;
    @(posedge vif.ack);
    @(posedge vif.clk);
    ->drvnext;
  endtask
  
  task read();
    @(posedge vif.clk);
    vif.rst<=1'b0;
    vif.strb<=1'b1;
    vif.wr<=1'b0;
    vif.addr<=tr.addr;
    @(posedge vif.ack);
    @(posedge vif.clk);
    ->drvnext;
  endtask
  
  task random();
    @(posedge vif.clk);
    vif.strb<=1'b1;
    vif.wr<=tr.wr;
    vif.addr<=tr.addr;
    vif.rst<=1'b0;
    if(vif.wr==1'b1)begin
      
      vif.wdata<=tr.wdata;
    end
    @(posedge vif.ack);
    @(posedge vif.clk);
    ->drvnext;
  endtask 
  
  task run();
    forever begin
      
    mbxgd.get(tr);
    if(tr.mode==0)begin
      write();
    end
    else if(tr.mode==1)begin
      read();
    end
    else if(tr.mode==2)begin
      random();
    end
    end
  endtask
endclass


//////////////////////////////////////////////////////////////////////////////////////////////////////////////

class monitor;
  
  transaction tr;
  virtual wb_if vif;
  mailbox #(transaction) mbxms;
  
  function new(mailbox #(transaction) mbxms);
    this.mbxms=mbxms;
  endfunction
  
  task run();
    tr=new();
    forever begin
      wait(vif.rst==1'b0);
      repeat(5)@(posedge vif.clk);
      @(posedge vif.clk);
      if (vif.strb==1'b0)begin
        tr.strb=vif.strb;
        repeat(2)@(posedge vif.clk);
        mbxms.put(tr);
      end
      else begin
        @(posedge vif.ack);
        tr.wr<=vif.wr;
        tr.strb<=vif.strb;
        tr.addr<=vif.addr;
        tr.wdata<=vif.wdata;
        tr.rdata<=vif.rdata;
        @(posedge vif.clk);
        mbxms.put(tr);
      end
    end
  endtask
endclass

///////////////////////////////////////////////////////////////////////////////////////////////////////////////
      
class scoreboard ;
  transaction tr;
  event sconext;
  mailbox #(transaction) mbxms;
  bit [7:0] data[256] ='{default:0};
  
  function new(mailbox #(transaction) mbxms);
    this.mbxms=mbxms;
  endfunction
  
  task run();
    forever begin
      mbxms.get(tr);
      if (tr.strb==1'b0)begin
        $display("[Sco] : Invalid Operation ");
      end
      else begin
        if(tr.wr==1'b1)begin
          data[tr.addr]<=tr.wdata;
          $display("[SCO] : Data Write Successfully  Data : %0d  addr : %0d  ",tr.wdata,tr.addr);
        end
        else begin
          if (tr.rdata==8'h11) begin
            $display(" [SCO] : Data Matched : Default value ");
          end
        else if (tr.rdata==data[tr.addr]) begin
          $display("[SCO] : Data Matched  Data  : %0d   addr : %0d ", tr.rdata, tr.addr);
        end
        else begin 
          $display ("[SCO] ; Data Mismatched  : Data  : %0d  addr : %0d  ",tr.wdata, tr.addr);
        end
        end
      end
      ->sconext;
    end
  endtask 
endclass

      

//////////////////////////////////////////////////////////////////////////////////////////////////////

module tb;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  mailbox #(transaction) mbxgd;
  mailbox #(transaction) mbxms;
  
  wb_if vif();
  event done,drvnext,sconext;
  
  mv_wb dut(vif.wr,vif.strb,vif.clk,vif.rst,vif.addr,vif.wdata,vif.rdata,vif.ack);
  
  initial begin
    vif.clk<=1'b0;
  end
   always #5 vif.clk=~vif.clk;
  
  initial begin
    mbxgd=new();
    mbxms=new();
    gen=new(mbxgd);
    drv=new(mbxgd);
    mon=new(mbxms);
    sco=new(mbxms);
    
    gen.count=10;
    
    drv.vif=vif;
    mon.vif=vif;
    
    drv.drvnext=drvnext;
    gen.drvnext=drvnext;
    gen.sconext=sconext;
    sco.sconext=sconext;
  end
  
  initial begin
    drv.reset();
    fork 
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_none
    wait(gen.done.triggered);
    $finish();
  end
  
  initial begin
    $dumpfile("whisbone.vcd");
    $dumpvars;
  end
endmodule
  
        
  
  
  

    
    
  
    
  
